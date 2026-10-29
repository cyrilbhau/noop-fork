#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Training tab root (redesign round 2 "04 Training"). Every figure comes from an existing read:
/// workout rows from `Repository.workoutRows` (the Workouts screen's read), lift sessions and sets from the
/// lift-log store (as Lift Log reads them), and the daily Strain bars from `StrainDetailModel` (the Strain
/// screen's own funnel, so today's bar matches the Today ring). Links lead to the existing screens: all
/// workouts and Lift Log push `MoreDestination` values onto the tab's bound path, a session opens the
/// existing workout or lift-session detail, "Paste a workout" opens the preview-before-save importer, and
/// "+" opens the B6 add sheet whose rows route to the existing flows.
struct TrainingHubView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var liftSession: LiftSessionController
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue
    @AppStorage(NoopTheme.Keys.ringsFillOnLoad) private var ringsFillOnLoad = true

    @State private var sessions: [TrainingSession] = []
    @State private var strainBars: [String: Double] = [:]
    @State private var loaded = false
    @State private var detail: DetailTarget?
    @State private var liftDetail: LiftTarget?
    @State private var pastingWorkout = false
    @State private var showAdd = false
    @State private var pendingAdd: TrainingAddAction?
    @State private var showLiftLog = false
    @State private var showDataSources = false
    @State private var recordTrigger = false
    @State private var pastTrigger = false

    private static let topAnchorID = "training-top"
    private static let recentCount = 5
    /// Three calendar months, plus a margin, of workout rows for the consistency calendar.
    private static let historyDays = 100

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// Wraps a tapped row so `.sheet(item:)` can present its detail (mirrors `WorkoutsView`).
    private struct DetailTarget: Identifiable {
        let row: WorkoutRow
        let id = UUID()
    }

    private struct LiftTarget: Identifiable {
        let session: LiftSessionRow
        let id = UUID()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topAnchorID)
                    header
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                    HStack(spacing: NoopTheme.Layout.cardGap) {
                        sessionsTile
                        strainTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .noopSkeleton(!loaded, cornerRadius: NoopTheme.Layout.tileRadius)
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .padding(.top, NoopTheme.Layout.l)
                    .noopEntrance(index: 0)
                    consistencyCard
                        .noopSkeleton(!loaded)
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.top, NoopTheme.Layout.cardGap)
                        .noopEntrance(index: 1)
                    volumeCard
                        .noopSkeleton(!loaded)
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.top, NoopTheme.Layout.cardGap)
                        .noopEntrance(index: 2)
                    recentHeader
                    recentCard
                        .noopSkeleton(!loaded)
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .noopEntrance(index: 3)
                    pasteCard
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.top, NoopTheme.Layout.cardGap)
                        .noopEntrance(index: 4)
                    linksCard
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.top, NoopTheme.Layout.cardGap)
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
        .trainingAmbient(.training, intensityRaw: ambientIntensityRaw)
        .refreshable { await repo.refresh() }
        .task(id: "\(repo.refreshSeq)-\(liftSession.savedSessions)-\(dayCycleModeRaw)") { await load() }
        .sheet(item: $detail) { target in
            NavigationStack {
                WorkoutDetailView(row: target.row)
                    .environmentObject(repo)
            }
            .noopSheetPresentation(largeFirst: true)
        }
        .sheet(item: $liftDetail) { target in
            LiftSessionDetailSheet(session: target.session) { await repo.refresh(); await load() }
                .environmentObject(repo)
        }
        .sheet(isPresented: $pastingWorkout) {
            WorkoutTextImportSheet { await repo.refresh(); await load() }
                .environmentObject(repo)
        }
        .sheet(isPresented: $showAdd, onDismiss: runPendingAdd) {
            TrainingAddSheet(liftSessionActive: liftSession.isActive) { action in
                pendingAdd = action
                showAdd = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showLiftLog) { MoreDestination.liftLog.destination }
        .navigationDestination(isPresented: $showDataSources) { MoreDestination.dataSources.destination }
        // The live-workout and past-workout flows observe AppModel / IntelligenceEngine, which publish
        // often; a zero-size leaf owns them so this screen does not re-render with every heartbeat.
        .background(TrainingFlowHost(recordTrigger: $recordTrigger, pastTrigger: $pastTrigger,
                                     onSaved: { await load() }))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: NoopTheme.Layout.m) {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                Text("Training")
                    .noopFont(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: weekLine).noopFont(.footnote)
            }
            Spacer(minLength: NoopTheme.Layout.s)
            NoopIconButton(systemImage: "plus", accessibilityLabel: "Add training") { showAdd = true }
        }
    }

    /// The current calendar week (the user's locale decides the first weekday).
    private var week: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())
            ?? DateInterval(start: Calendar.current.startOfDay(for: Date()), duration: 7 * 86_400)
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// "This week · 27 Oct – 2 Nov".
    private var weekLine: String {
        let first = weekDays.first ?? week.start
        let last = weekDays.last ?? week.end
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return String(localized: "This week · \(first.formatted(style)) – \(last.formatted(style))")
    }

    // MARK: - Tiles

    private var sessionsThisWeek: Int {
        let lo = Int(week.start.timeIntervalSince1970), hi = Int(week.end.timeIntervalSince1970)
        return sessions.filter { $0.startTs >= lo && $0.startTs < hi }.count
    }

    /// No sessions-per-week goal exists in NOOP, so the ring shows the count on a bare track (no fill
    /// toward an invented target).
    private var sessionsTile: some View {
        // Ring above the label, like the Strain tile beside it: side by side, a half-width tile at 402 pt
        // left "Sessions" too narrow and it broke mid-word.
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            NoopRing(value: 0, color: NoopTheme.strain, lineWidth: TrainingLayout.hubRingLine,
                     diameter: TrainingLayout.hubRing, label: loaded ? "\(sessionsThisWeek)" : "—",
                     animate: false,
                     accessibilityLabel: String(localized: "Sessions this week"),
                     accessibilityValue: "\(sessionsThisWeek)")
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                Text("Sessions").noopFont(.rowTitle)
                Text("This week · no goal set").noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NoopTheme.Layout.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .noopGlassBackground(cornerRadius: NoopTheme.Layout.tileRadius)
    }

    /// The week's daily Strain values as bars. There is no weekly Strain aggregate in NOOP, so the tile
    /// shows each day's stored value (today's is the same effective value the Today ring shows); a day
    /// with no Strain, or still ahead, is an empty bar.
    private var strainTile: some View {
        let values = weekDays.map { strainBars[Self.dayKey($0)] }
        let todayIndex = weekDays.firstIndex { Calendar.current.isDateInToday($0) }
        let maxValue = effortScale == .whoop ? 21.0 : 100.0
        return VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            NoopBarChart(values: values.map { $0.map { UnitFormatter.effortValue($0, scale: effortScale) } },
                         color: NoopTheme.strain, maxValue: maxValue, highlightedIndex: todayIndex,
                         animates: NoopTheme.Motion.ringsAnimate(reduceMotion: reduceMotion,
                                                                fillOnLoad: ringsFillOnLoad),
                         accessibilityLabel: Text("Daily Strain this week"),
                         valueFormat: { String(format: "%.1f", $0) })
                .frame(height: TrainingLayout.weekBarsHeight)
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                Text("Strain").noopFont(.rowTitle)
                Text("Each day this week").noopFont(.footnote)
            }
        }
        .padding(NoopTheme.Layout.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .noopGlassBackground(cornerRadius: NoopTheme.Layout.tileRadius)
    }

    // MARK: - Consistency

    private enum DayKind { case lift, cardio, rest }

    /// The last three calendar months, oldest first, each as its first day.
    private var months: [Date] {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: Date())?.start ?? cal.startOfDay(for: Date())
        return (0..<3).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: thisMonth) }
    }

    private var dayKinds: [String: DayKind] {
        var kinds: [String: DayKind] = [:]
        for s in sessions {
            let key = Self.dayKey(Date(timeIntervalSince1970: TimeInterval(s.startTs)))
            if s.isLift { kinds[key] = .lift } else if kinds[key] == nil { kinds[key] = .cardio }
        }
        return kinds
    }

    private var consistencyCard: some View {
        let kinds = dayKinds
        let first = months.first ?? Date()
        let firstTs = Int(first.timeIntervalSince1970)
        let count = sessions.filter { $0.startTs >= firstTs }.count
        let monthStyle = Date.FormatStyle.dateTime.month(.abbreviated)
        let span = "\(first.formatted(monthStyle)) – \(Date().formatted(monthStyle))"
        return NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
                HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
                    ForEach(months, id: \.self) { month in
                        monthGrid(month, kinds: kinds)
                    }
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                        Text("Consistency").noopFont(.rowTitle)
                        Text(verbatim: count == 1
                             ? String(localized: "\(span) · 1 session")
                             : String(localized: "\(span) · \(count) sessions"))
                            .noopFont(.footnote)
                    }
                    Spacer(minLength: NoopTheme.Layout.s)
                    HStack(spacing: NoopTheme.Layout.m) {
                        legend(Text("Lift"), color: NoopTheme.lift)
                        legend(Text("Cardio"), color: NoopTheme.strain)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func monthGrid(_ month: Date, kinds: [String: DayKind]) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let range = cal.range(of: .day, in: .month, for: month) ?? 1..<29
        let days: [Date] = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
            .filter { $0 <= today }
        // `.flexible()` alone defaults to a 10 pt minimum per column, which made three month grids wider than
        // a 402 pt screen and pushed the whole hub past its gutters; the dot size is the real minimum.
        let columns = Array(repeating: GridItem(.flexible(minimum: TrainingLayout.dot), spacing: TrainingLayout.dotGap),
                            count: 7)
        return VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            Text(verbatim: month.formatted(.dateTime.month(.abbreviated)))
                .noopFont(.caption, color: false)
                .foregroundStyle(NoopTheme.textSecondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: TrainingLayout.dotGap) {
                ForEach(days, id: \.self) { day in
                    dot(kinds[Self.dayKey(day)] ?? .rest, isToday: cal.isDate(day, inSameDayAs: today))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dot(_ kind: DayKind, isToday: Bool) -> some View {
        let fill: Color = {
            switch kind {
            case .lift: return NoopTheme.lift
            case .cardio: return NoopTheme.strain
            case .rest: return NoopTheme.track
            }
        }()
        return Circle()
            .fill(fill)
            .frame(width: TrainingLayout.dot, height: TrainingLayout.dot)
            .overlay {
                if isToday {
                    Circle()
                        .strokeBorder(NoopTheme.textPrimary, lineWidth: TrainingLayout.todayRingLine)
                        .padding(-TrainingLayout.todayRingInset - TrainingLayout.todayRingLine)
                }
            }
    }

    private func legend(_ label: Text, color: Color) -> some View {
        HStack(spacing: TrainingLayout.sourceGap) {
            Circle().fill(color).frame(width: TrainingLayout.dot, height: TrainingLayout.dot)
            label.noopFont(.caption)
        }
    }

    // MARK: - Volume

    /// Σ weight × reps over working sets logged in the last 7 days (`LiftMetrics.volumeLoadKg`, weights as
    /// logged). Nil when no countable set was logged.
    private var weekVolumeKg: Double? {
        let cutoff = Int(Date().timeIntervalSince1970) - 7 * 86_400
        let volumes = sessions.filter { $0.startTs >= cutoff }.compactMap(\.volumeKg)
        return volumes.isEmpty ? nil : volumes.reduce(0, +)
    }

    private var volumeCard: some View {
        NoopGlassCard {
            HStack(alignment: .center, spacing: NoopTheme.Layout.m) {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                    Text("Volume lifted").noopFont(.rowTitle)
                    Text("Last 7 days · from logged sets").noopFont(.footnote)
                }
                Spacer(minLength: NoopTheme.Layout.s)
                if let kg = weekVolumeKg {
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
                        Text(verbatim: TrainingFormat.groupedMass(kg, system: unitSystem)).noopFont(.statNumber)
                        Text(verbatim: LiftFormat.weightUnit(unitSystem)).noopFont(.unit)
                    }
                } else {
                    Text(verbatim: "—").noopFont(.statNumber, color: false)
                        .foregroundStyle(NoopTheme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recent

    private var recentHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent")
                .noopFont(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoopTheme.Layout.s)
            NavigationLink(value: MoreDestination.workouts) {
                HStack(spacing: NoopTheme.Layout.xs / 2) {
                    Text("All")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .noopFont(.bodySmall, color: false)
                .foregroundStyle(NoopTheme.textSecondary)
                .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("All workouts"))
        }
        .padding(.top, NoopTheme.Layout.sectionTop - NoopTheme.Layout.m)
        .padding(.horizontal, NoopTheme.Layout.sectionSide)
    }

    @ViewBuilder private var recentCard: some View {
        let recent = Array(sessions.prefix(Self.recentCount))
        if recent.isEmpty {
            NoopGlassCard {
                Text(loaded ? "No workouts yet" : "Loading your sessions…")
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
            }
        } else {
            NoopGlassCard(flush: true) {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { TrainingDivider() }
                        Button { open(session) } label: { sessionRow(session) }
                            .buttonStyle(.noopPress)
                    }
                }
            }
        }
    }

    private func open(_ session: TrainingSession) {
        if let lift = session.lift {
            liftDetail = LiftTarget(session: lift)
        } else if let row = session.workout {
            detail = DetailTarget(row: row)
        }
    }

    /// "Today · 6 exercises · 21 sets" for a lift, "Mon · 5.2 km" for a distance workout.
    private func subtitle(_ session: TrainingSession) -> String {
        var parts = [TrainingFormat.relativeDay(session.startTs)]
        let performed = session.performedSets
        if !performed.isEmpty {
            let exercises = Set(performed.map(\.exercise)).count
            let sets = performed.filter { !$0.isWarmup }.count
            parts.append(String(localized: "\(exercises) exercises · \(sets) sets"))
        } else if let m = session.workout?.distanceM, m > 0 {
            let system = UnitPrefs.resolveDistance(system: unitSystem, override: distanceSystemRaw)
            parts.append(UnitFormatter.distanceFromMeters(m, system: system))
        }
        return parts.joined(separator: " · ")
    }

    private func sessionRow(_ session: TrainingSession) -> some View {
        HStack(spacing: NoopTheme.Layout.m) {
            DomainIcon(systemImage: session.symbol, color: session.tint)
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                // Sport and program names are data, never catalogue keys.
                Text(verbatim: session.title).noopFont(.rowTitle).lineLimit(1)
                Text(verbatim: subtitle(session)).noopFont(.footnote).lineLimit(1)
                TrainingSourceLine(provenance: session.provenance)
                    .padding(.top, NoopTheme.Layout.xs / 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: NoopTheme.Layout.xs / 2) {
                if let strain = session.workout?.strain {
                    Text(verbatim: UnitFormatter.effortDisplay(strain, scale: effortScale))
                        .noopFont(.rowNumber, color: false)
                        .foregroundStyle(NoopTheme.strain)
                }
                if let duration = TrainingFormat.duration(session.durationSeconds) {
                    Text(verbatim: duration).noopFont(.caption)
                }
            }
        }
        .padding(.vertical, NoopTheme.Layout.m)
        .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Paste and links

    private var pasteCard: some View {
        Button { pastingWorkout = true } label: {
            NoopGlassCard {
                HStack(spacing: NoopTheme.Layout.m) {
                    DomainIcon(systemImage: "doc.on.clipboard", color: NoopTheme.textPrimary)
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                        Text("Paste a workout").noopFont(.rowTitle)
                        Text("Preview before it saves").noopFont(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(NoopTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.noopPress)
        .accessibilityElement(children: .combine)
    }

    private var linksCard: some View {
        NoopGlassCard(flush: true) {
            VStack(spacing: 0) {
                NavigationLink(value: MoreDestination.liftLog) {
                    NoopListRow("Lift Log", systemImage: "dumbbell.fill", color: NoopTheme.lift,
                                detail: String(localized: "Programs, sessions and sets"), showsDivider: false)
                }
                .buttonStyle(.plain)
                NavigationLink(value: MoreDestination.workouts) {
                    NoopListRow("Workouts", systemImage: "figure.run", color: NoopTheme.strain,
                                detail: String(localized: "Every session, threaded together."))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Add sheet routing

    /// Runs after the add sheet has fully dismissed, so the next presentation never races it.
    private func runPendingAdd() {
        guard let action = pendingAdd else { return }
        pendingAdd = nil
        switch action {
        case .record: recordTrigger = true
        case .liftSession:
            // Same guard Lift Log applies before starting: a running session is reopened, not doubled.
            if liftSession.isActive { liftSession.isPresented = true } else { showLiftLog = true }
        case .paste: pastingWorkout = true
        case .hevyCSV: showDataSources = true
        case .pastWorkout: pastTrigger = true
        }
    }

    // MARK: - Load

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(_ date: Date) -> String {
        keyFormatter.timeZone = .current
        return keyFormatter.string(from: date)
    }

    private func load() async {
        let workouts = await repo.workoutRows(days: Self.historyDays)
        var lifts: [LiftSessionRow] = []
        var sets: [String: [LiftSetRow]] = [:]
        if let store = await repo.storeHandle() {
            let now = Int(Date().timeIntervalSince1970)
            let from = now - Self.historyDays * 86_400
            // The same two namespaces Lift Log lists: sessions logged here and reviewed imports.
            lifts = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: from, toTs: now)) ?? []
            if repo.deviceId != PersonalLiftingImport.deviceId {
                lifts += (try? await store.liftSessions(deviceId: PersonalLiftingImport.deviceId,
                                                        fromTs: from, toTs: now)) ?? []
            }
            lifts = lifts.filter { $0.endTs != nil }   // an abandoned session is not history
            // Sets only where they are shown: the recent rows and the 7-day volume.
            let weekAgo = now - 7 * 86_400
            let newest = lifts.sorted { $0.startTs > $1.startTs }.prefix(Self.recentCount).map(\.id)
            for lift in lifts where lift.startTs >= weekAgo || newest.contains(lift.id) {
                sets[lift.id] = (try? await store.liftSets(sessionId: lift.id)) ?? []
            }
        }
        sessions = TrainingSession.merge(workouts: workouts, lifts: lifts, sets: sets)
        loaded = true

        let strain = await StrainDetailModel.load(dayKey: nil, repo: repo, profile: profile,
                                                  mode: DayCycleMode.persisted(dayCycleModeRaw))
        var bars: [String: Double] = [:]
        for (key, value) in zip(strain.barKeys, strain.bars) { if let value { bars[key] = value } }
        strainBars = bars
    }
}

// MARK: - Flow host

/// Hosts the two add flows that observe frequently-publishing objects: recording a live workout (the same
/// sequence as `WorkoutStartControl`: name the sport, start, open `LiveWorkoutView`; or reopen the running
/// one) and adding a past workout (`ManualWorkoutSheet` saved and rescored as the Workouts screen does).
private struct TrainingFlowHost: View {
    @Binding var recordTrigger: Bool
    @Binding var pastTrigger: Bool
    let onSaved: () async -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @State private var showLiveWorkout = false
    @State private var showStartSport = false
    @State private var showPastWorkout = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: recordTrigger) { _, fire in
                guard fire else { return }
                recordTrigger = false
                if model.activeWorkout == nil { showStartSport = true } else { showLiveWorkout = true }
            }
            .onChange(of: pastTrigger) { _, fire in
                guard fire else { return }
                pastTrigger = false
                showPastWorkout = true
            }
            .sheet(isPresented: $showLiveWorkout) {
                LiveWorkoutView(onClose: { showLiveWorkout = false })
                    .environmentObject(model.live)
            }
            .workoutSelectionCover(isPresented: $showStartSport) {
                StartWorkoutSheet { name in
                    model.startWorkout(sport: name)
                    showLiveWorkout = true
                }
            }
            .sheet(isPresented: $showPastWorkout) {
                ManualWorkoutSheet(editing: nil) { row, _ in
                    Task {
                        await repo.saveManualWorkout(row, replacing: nil)
                        // #598: rescore the new workout from the strap's HR now, as WorkoutsView does.
                        await intelligence.analyzeRecent()
                        await onSaved()
                    }
                }
            }
    }
}
#endif
