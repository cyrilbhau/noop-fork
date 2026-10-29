#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the shell is a
/// native `TabView` with **Today · Sleep · Training · Health**, plus **Coach** (on iOS 26 the system's
/// separate circular search-role tab; on iOS 17–25 an ordinary fifth tab). Everything the old "More" tab
/// listed now lives in the **Profile** sheet, opened from the avatar at the top-right of each tab
/// (redesign Phase 2, `docs/personal/REDESIGN-IMPLEMENTATION.md`).
struct RootTabView: View {
    /// The Coach master switch, under the same `noop.` key Android writes. Default ON, so every install
    /// that shipped with the tab is unchanged.
    ///
    /// Not tab chrome: with this off the AI is off. The tab goes, the Today launcher card goes, and the
    /// daily brief is cancelled, because the brief calls a provider from the BACKGROUND with no UI
    /// attached and would otherwise keep posting AI notifications for a feature the wearer switched off.
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    /// #1841: shared with Android by NAME and meaning, not by storage — the two platforms keep their own
    /// stores, exactly as the Clock format setting does.
    ///
    /// Default FALSE here while Android defaults true, and the divergence is deliberate. Apple's forums
    /// report `.tabBarMinimizeBehavior(.onScrollDown)` failing to trigger in tabs built on
    /// `NavigationStack(path:)` — which is every primary tab in this file, bound deliberately so a tab
    /// root can pop and re-scroll. So this may well be inert on our structure, and defaulting ON would
    /// advertise a behaviour that never happens. Off until someone confirms it on an iOS 26 device.
    @AppStorage("noop.bottomBarAutoHide") private var bottomBarAutoHide = false

    /// The live gym session, owned at the app root — see `LiftSessionController`.
    @EnvironmentObject private var liftSession: LiftSessionController
    /// External entry points must wait until the mandatory first-run gates have completed. The root owns
    /// that state; keeping it explicit here prevents this shell's window-level sheet from covering a gate.
    let homeScreenQuickActionsEnabled: Bool

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.scenePhase) private var scenePhase
    /// Cross-screen navigation requests (e.g. Live → "Manage devices"). Devices isn't a tab, so a request
    /// presents it as a sheet, matching the quick-action screens (or pushes it inside Profile when that
    /// sheet is already up — see `profileRoute(for:)`).
    @EnvironmentObject private var router: NavRouter
    /// The scene-local receiver for actions chosen from NOOP's Home Screen icon menu.
    @EnvironmentObject private var homeScreenQuickActions: HomeScreenQuickActionSceneDelegate

    /// Which quick-action screen the centre FAB is presenting (nil = sheet closed).
    @State private var quickAction: QuickAction?
    /// Presents the Devices manager (pair / switch bands) when a screen asks the shell to open it.
    @State private var showDevices = false
    /// A routed v5 pillar screen (Insights hub / Lab Book / fused record / Rhythm / Trends) presented as a
    /// sheet when a screen deep-links to it via NavRouter. nil = closed.
    @State private var routedPillar: NavRouter.Destination?
    /// The Profile sheet (replaces the More tab) and its own navigation path. The path lives here, not in
    /// the sheet, so a router request arriving while Profile is up can push onto it (SwiftUI will not
    /// present a second sheet over the first).
    @State private var showProfile = false
    @State private var profilePath = NavigationPath()
    /// Selected tab — bound so tab switches can crossfade (README §Motion: ~240ms opacity swap
    /// between tab roots, calm easing). Defaults to Today.
    @State private var selectedTab: Int = TabTag.today
    /// One `NavigationPath` per tab, indexed by tab tag. Re-tapping the already-active tab pops
    /// that tab's stack to its root (#135) by clearing its path — an animated pop that leaves the
    /// root view alive, so an at-root re-tap keeps scroll position and never re-runs `.task`
    /// (#198; the #197 resetID/`.id()` rebuild reset both). Requires the tab roots' first-hop
    /// links to push `TabRoute`/`MoreDestination` VALUES — closure-destination links bypass the path.
    @State private var tabPaths: [NavigationPath] = Array(repeating: NavigationPath(), count: TabTag.count)
    /// One scroll-to-top token per tab. Bumped when the user re-taps the active tab while it's ALREADY
    /// at its root — the other half of the iOS convention #197/#198 left unserved (an at-root re-tap was
    /// a no-op). Threaded into each tab's root via `\.scrollToTopSignal`; ScreenScaffold / LiquidTodayView
    /// scroll to their top anchor when their tab's token changes.
    @State private var scrollTop: [Int] = Array(repeating: 0, count: TabTag.count)

    /// V8 liquid redesign is the default Today; the Settings toggle lets a user fall back to the classic
    /// Today if they prefer it (keyed identically to the SettingsView toggle). Default ON.
    @AppStorage("noop.liquidTodayEnabled") private var liquidTodayEnabled = true

    /// The Today tab root, honouring the liquid/classic preference.
    @ViewBuilder private var todayTabRoot: some View {
        if liquidTodayEnabled { LiquidTodayView() } else { TodayView() }
    }

    /// Native tab selection binding. SwiftUI sends taps on the already-selected item through the
    /// setter, which lets the system tab bar retain the app's refresh / pop-to-root / scroll-to-top
    /// convention without placing a custom hit-testing layer over the platform bar.
    private var nativeTabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { tag in
                if tag == selectedTab {
                    reselectTab(tag)
                } else {
                    selectedTab = tag
                }
            }
        )
    }

    private func reselectTab(_ tag: Int) {
        Task { await repo.refresh() }
        if !tabPaths[tag].isEmpty {
            tabPaths[tag] = NavigationPath()
        } else {
            scrollTop[tag] += 1
        }
    }

    /// Opens Profile at its root. A fresh path each time: Profile is a sheet, not a tab, so re-opening it
    /// should not land the wearer three screens deep in whatever they left last time.
    private func openProfile() {
        profilePath = NavigationPath()
        withAnimation(Self.sheetEase) { showProfile = true }
    }

    /// The tags the tab-swipe gesture walks, in bar order. Coach joins only while its tab exists, so a
    /// swipe can never land on a tag no tab claims (which renders as a blank tab).
    private var swipeOrder: [Int] {
        coachEnabled ? TabTag.primary + [TabTag.coach] : TabTag.primary
    }

    /// The anywhere-swipe tab-switch drag (2026-07-02). Held as a property so the attachment site can
    /// enable or disable it through a `GestureMask` instead of attaching it conditionally: a conditional
    /// attachment changes view identity, and this condition toggles on every push and pop, which would
    /// rebuild the tab roots underneath it. The same class of rebuild is what #197 caused with an
    /// `.id()` reset and #198 had to undo — it lost scroll position and re-ran `.task`.
    ///
    /// Only a decisive horizontal flick switches tabs, and Today is carved out because it uses
    /// horizontal swipe to change DAYS. Both thresholds are unchanged from the original gesture.
    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                // Today uses horizontal swipe to change DAYS, so tab-swipe is off there.
                guard selectedTab != TabTag.today else { return }
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.6 else { return }
                let order = swipeOrder
                guard let index = order.firstIndex(of: selectedTab) else { return }
                let next = order[min(order.count - 1, max(0, index + (dx < 0 ? 1 : -1)))]
                if next != selectedTab {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = next }
                }
            }
    }

    // MARK: - Tab container

    /// The native tab bar. The availability check is fixed for the life of the process, so it picks one
    /// branch once and never flips view identity (the #519 lesson documented on `noopTabBarAutoHide`).
    ///
    /// The tags stay LITERAL (`TabTag`) rather than being renumbered when Coach is absent: `tabPaths` and
    /// `scrollTop` are indexed by tag, and Coach is the last tag in both shapes, so a flip of the master
    /// switch never shifts another tab's navigation path or scroll position onto a different tab.
    @ViewBuilder private var tabContainer: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: nativeTabSelection) {
                Tab("Today", systemImage: "square.grid.2x2", value: TabTag.today) { todayStack }
                Tab("Sleep", systemImage: "bed.double", value: TabTag.sleep) { sleepStack }
                Tab("Training", systemImage: "dumbbell", value: TabTag.training) { trainingStack }
                Tab("Health", systemImage: "heart", value: TabTag.health) { healthStack }
                // The search role is what makes iOS 26 draw Coach as the separate circle beside the bar.
                // Conditional on the master switch, exactly as the pre-26 tab below.
                if coachEnabled {
                    Tab("Coach", systemImage: "sparkles", value: TabTag.coach, role: .search) { coachStack }
                }
            }
        } else {
            TabView(selection: nativeTabSelection) {
                todayStack
                    .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                    .tag(TabTag.today)
                sleepStack
                    .tabItem { Label("Sleep", systemImage: "bed.double") }
                    .tag(TabTag.sleep)
                trainingStack
                    .tabItem { Label("Training", systemImage: "dumbbell") }
                    .tag(TabTag.training)
                healthStack
                    .tabItem { Label("Health", systemImage: "heart") }
                    .tag(TabTag.health)
                if coachEnabled {
                    coachStack
                        .tabItem { Label("Coach", systemImage: "sparkles") }
                        .tag(TabTag.coach)
                }
            }
        }
    }

    // Today draws its own avatar in its header (it opens Profile through `\.openProfile`), so only the
    // other tabs carry the toolbar avatar. Coach carries none: on iOS 26 it is the separate circle rather
    // than one of the four tabs, and its own header holds its connection controls.
    private var todayStack: some View {
        tabStack(todayTabRoot, tag: TabTag.today, profileInToolbar: false)
    }
    private var sleepStack: some View {
        tabStack(SleepView(), tag: TabTag.sleep, profileInToolbar: true)
    }
    private var trainingStack: some View {
        tabStack(TrainingHubView(), tag: TabTag.training, profileInToolbar: true)
    }
    private var healthStack: some View {
        tabStack(HealthHubView(), tag: TabTag.health, profileInToolbar: true)
    }
    private var coachStack: some View {
        tabStack(CoachView(), tag: TabTag.coach, profileInToolbar: false)
    }

    var body: some View {
        // The platform tab bar is intentionally left fully native. iOS 26 supplies Liquid Glass and
        // its dynamic interaction with scrolling content automatically; older supported releases use
        // the corresponding system material and safe-area behaviour from the same TabView.
        tabContainer
        .tint(StrandPalette.accent)
        // Today's header avatar (Liquid and classic) reads this to open Profile instead of Settings.
        .environment(\.openProfile, OpenProfileAction { openProfile() })
        // Switching Coach off while STANDING on it leaves `selectedTab` pointing at a tag no tab claims
        // any more, which renders as an empty tab rather than as an error. Send that wearer to Today, and
        // only in that case, so a flip made from anywhere else does not move them.
        .onChangeCompat(of: coachEnabled) { enabled in
            coach.applyCoachMasterSwitch()
            if !enabled && selectedTab == TabTag.coach { selectedTab = TabTag.today }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { coach.resumeChatGPTConnection() }
        }
        // #1841: the same "Hide bar when scrolling" preference Android drives its own bar with. Here the
        // system owns the behaviour — iOS 26's tab bar MINIMISES to a pill on scroll down rather than
        // sliding away entirely, so this is the platform's read of the same intent, not a copy of ours.
        .noopTabBarAutoHide(bottomBarAutoHide)
            // Tab crossfade — README §Motion: ~240ms opacity swap between tab roots, global calm
            // easing cubic-bezier(0.22,1,0.36,1).
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: selectedTab)
            // Swipe left/right anywhere to move between tabs (2026-07-02), but ONLY while the current
            // tab is at its root. Attaching this ancestor drag gesture unconditionally defeated the
            // edge-restriction of a pushed NavigationStack screen's native interactive-pop gesture —
            // any pushed subscreen (Workouts, Lift Log, …) became draggable/rubber-banding from
            // anywhere, not just the left edge (#519). Disabling the recognizer once a push is active,
            // rather than just gating the onEnded action, is what stops the interference: the action
            // never runs early enough, because the recognizer competes during recognition.
            //
            // The mask does that WITHOUT changing view identity. #519 attached the gesture through a
            // conditional ViewModifier, which put the two states in separate _ConditionalContent
            // branches — and since this condition toggles on every push and pop, each navigation
            // rebuilt the whole TabView subtree and could reset @State inside the tab roots (scroll
            // offsets, chart ranges, expanded sections). `including:` keeps one view type in both
            // states, so nothing is torn down.
            //
            // The mask MUST be `.subviews`, not `.none`. `.subviews` means "enable the subview
            // hierarchy's gestures, disable the added one" — exactly this requirement. `.none` disables
            // the subview hierarchy TOO, which on a pushed screen would take out scrolling, taps and the
            // interactive-pop itself: far worse than the bug being fixed.
            .simultaneousGesture(tabSwipeGesture,
                                 including: tabPaths[selectedTab].isEmpty ? .all : .subviews)
        .task {
            await repo.refresh()
            // Backup & Sync: on-launch catch-up (see RootView). Detached + utility priority so a
            // 100MB+ whole-DB ZIP never blocks startup; gated on the auto toggle (default OFF). (Must-fix #4.)
            let backupRepo = repo
            Task.detached(priority: .utility) {
                await FolderBackup.catchUpIfDue(checkpoint: { await backupRepo.checkpointForBackup() })
            }
        }
        // Quick-action sheet presents with the calm easing (~0.42s) per the README sheet spec —
        // the easing is applied where `quickAction` is set (see `presentQuickAction`), keeping the
        // animation scoped to the sheet rather than the whole shell.
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
        }
        // Live's "Manage devices" affordance (and any future cross-screen link to Devices) routes here:
        // present the Devices manager in its own nav stack, the same way the quick-action screens do.
        .sheet(isPresented: $showDevices) {
            devicesScreen
        }
        // v5 pillar deep-links (Insights hub / Lab Book / fused record / Rhythm / Trends) present as a
        // sheet in their own nav stack — the same idiom the quick-action + Devices screens use on iPhone.
        .sheet(item: $routedPillar) { dest in
            pillarScreen(dest)
        }
        // Profile (replaces the More tab): every former More row, the strap card and Settings.
        .sheet(isPresented: $showProfile) {
            ProfileSheet(path: $profilePath, onClose: { showProfile = false })
        }
        // Honour a router request: Devices keeps its dedicated sheet; the v5 pillars route through the
        // shared pillar sheet. Cleared so the same tap can fire again later.
        .onChange(of: router.requestedDestination) { _, dest in
            guard let dest else { return }
            // Profile is a sheet now, so a request from a screen pushed inside it cannot present another
            // sheet over it. Every destination Profile can host is pushed onto ITS stack instead; the two
            // that belong to a tab (Coach, Live Sessions on Today) close Profile and fall through.
            if showProfile {
                if let route = profileRoute(for: dest) {
                    profilePath.append(route)
                    router.requestedDestination = nil
                    return
                }
                showProfile = false
            }
            switch dest {
            case .devices:
                showDevices = true
                router.requestedDestination = nil
            case .insightsHub, .labBook, .fusedRecord, .rhythm, .alarms, .trends:
                // Trends stopped being a tab in the redesign (it lives under Profile › Insights), so a
                // deep link opens it in the shared pillar sheet like the other v5 screens.
                routedPillar = dest
                router.requestedDestination = nil
            case .coach:
                // K3: Coach is a top-level tab — switch to it directly instead of presenting it as a
                // pillar sheet.
                //
                // Guarded on the master switch, because this route is reachable with Coach OFF. A brief
                // notification already sitting in Notification Centre still calls `openCoach()` when it is
                // tapped (StrandApp wires `onCoachBriefTapped` to it), and with no tab claiming the Coach
                // tag the wearer would land on a BLANK tab. Dropping the request leaves them where they
                // were, which is the honest answer for a feature that is switched off.
                guard coachEnabled else {
                    router.requestedDestination = nil
                    break
                }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = TabTag.coach }
                router.requestedDestination = nil
            case .activeWorkout:
                // The Today active-workout indicator opens Live through the quick-action Live sheet; once
                // it's up, LiveView consumes the one-shot `presentActiveWorkout` flag and presents the
                // in-exercise screen. Calm sheet easing, matching the other quick-action presents.
                withAnimation(Self.sheetEase) { quickAction = .live }
                router.requestedDestination = nil
            case .liveSession:
                // Live Sessions is presented from Today's own Start entry (a cover, not a routed sheet),
                // so a deep-link lands on the Today tab where that entry lives.
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = TabTag.today }
                router.requestedDestination = nil
            case .journal:
                // The #627 Today journal widget opens the journal through the quick-action Journal sheet
                // (InsightsView), matching the FAB's "Log journal" action. Calm sheet easing.
                withAnimation(Self.sheetEase) { quickAction = .journal }
                router.requestedDestination = nil
            }
        }
        // A screen's top-bar "+" routes here: open the quick-action sheet, then clear the flag. If
        // Profile is up, close it first and present once its dismissal has finished.
        .onChange(of: router.quickActionsRequested) { _, req in
            if req {
                router.quickActionsRequested = false
                if showProfile {
                    showProfile = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        withAnimation(Self.sheetEase) { quickAction = .menu }
                    }
                } else {
                    withAnimation(Self.sheetEase) { quickAction = .menu }
                }
            }
        }
        // A cold-launch selection is already pending when this shell appears; a warm selection arrives
        // through the change callback. Both route through the same screens as the centre FAB.
        .onAppear {
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .onChange(of: homeScreenQuickActions.pendingAction) { _, _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .onChange(of: homeScreenQuickActionsEnabled) { _, _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        // The running gym session, reachable from ANY tab. It sits above the tab bar rather than
        // inside the Lift Log screen, because a workout outlives whichever screen you wandered to —
        // and because swiping the sheet away must minimise the session, not end it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if liftSession.isActive {
                LiftSessionBar()
                    .padding(.horizontal, 14)
                    // Clear the floating tab bar with the same constant every screen uses, or the
                    // session bar sits on top of the tab labels.
                    .padding(.bottom, NoopMetrics.tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: liftSession.isActive)
        // A session left running by a previous launch is back before this view exists
        // (`LiftSessionController.resumeSaved`, from `StrandiOSApp.init`), as the BAR — not as a sheet
        // thrown in the user's face; they open it when they want it.
        .sheet(isPresented: $liftSession.isPresented) {
            LiftSessionView { }
        }
    }

    /// Where a router destination lives inside the Profile sheet, or nil when it belongs to a tab. Used
    /// only while Profile is presented; otherwise the destinations keep their shell sheets.
    private func profileRoute(for dest: NavRouter.Destination) -> MoreDestination? {
        switch dest {
        case .devices:       return .devices
        case .insightsHub:   return .insightsHub
        case .labBook:       return .labBook
        case .fusedRecord:   return .fusedRecord
        case .rhythm:        return .rhythm
        case .alarms:        return .alarms
        case .trends:        return .trends
        // LiveView consumes the one-shot `presentActiveWorkout` flag on appear, pushed or presented.
        case .activeWorkout: return .live
        // The journal is hosted by InsightsView, the same screen the Journal quick action opens.
        case .journal:       return .insights
        case .coach, .liveSession: return nil
        }
    }

    /// Mandatory launch gates defer an external action. Once the shell is available, an explicit Home
    /// Screen choice supersedes any ordinary shell sheet; choosing the already-open destination simply
    /// consumes the request and leaves that screen in place.
    private func presentPendingHomeScreenQuickActionIfPossible() {
        guard homeScreenQuickActionsEnabled,
              let action = homeScreenQuickActions.pendingAction else { return }

        let destination: QuickAction = switch action {
        case .liveHeartRate: .live
        case .startWorkout: .workout
        case .logJournal: .journal
        case .breathe: .breathe
        }
        homeScreenQuickActions.consume(action)
        withAnimation(Self.sheetEase) {
            showDevices = false
            routedPillar = nil
            showProfile = false
            quickAction = destination
        }
    }

    /// A routed v5 pillar screen wrapped in its own nav stack + Done button (mirrors `quickScreen`).
    @ViewBuilder
    private func pillarScreen(_ dest: NavRouter.Destination) -> some View {
        NavigationStack {
            Group {
                switch dest {
                case .insightsHub: InsightsHubView()
                case .labBook: LabBookView()
                case .fusedRecord: FusedRecordHost()
                case .rhythm: RhythmHost(onClose: { routedPillar = nil })
                case .devices: DevicesView()
                // Trends is no longer a tab on iPhone; a deep link presents it here.
                case .trends: TrendsView()
                // .activeWorkout routes through the quick-action Live sheet (handled above); this keeps the
                // switch exhaustive and falls back to Live if it ever reaches the pillar host.
                case .activeWorkout: LiveView()
                // .liveSession routes to the Today tab (handled above — its Start entry owns the cover);
                // this keeps the switch exhaustive and falls back to Today if it ever reaches the host.
                case .liveSession: LiquidTodayView()
                // .journal opens through the quick-action Journal sheet (handled above); this keeps the
                // switch exhaustive and falls back to the journal's Insights host if it ever reaches here.
                case .journal: InsightsView()
                // .coach switches to the Coach tab (handled above — the morning-brief tap-through and the
                // #1862 launcher both arrive that way, the launcher's question riding on
                // `AICoachEngine.pendingPrompt`); this keeps the switch exhaustive and falls back to Coach if
                // it ever reaches the host.
                case .coach: CoachView()
                case .alarms: SmartAlarmView()
                }
            }
            // Trends and the Today fallback emit TabRoute value pushes (#198), which need a destination
            // registered in THIS sheet's stack to resolve.
            .tabRouteDestinations()
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // #1027: same fix as quickScreen — the pillar screens draw the full-bleed liquid sky, so a
            // transparent nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { routedPillar = nil }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    /// Calm-easing curve (cubic-bezier(0.22,1,0.36,1)) at the README sheet-present duration.
    private static let sheetEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    // MARK: - Quick-action sheet

    /// Routes a chosen quick action to the existing screen, or shows the action menu itself.
    @ViewBuilder
    private func quickActionDestination(_ action: QuickAction) -> some View {
        switch action {
        case .menu:
            QuickActionSheet { picked in
                // Swap the menu for the chosen destination on the next runloop so the sheet
                // re-presents cleanly (avoids dismiss/re-present races). Calm easing on re-present.
                quickAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Self.sheetEase) { quickAction = picked }
                }
            }
            .presentationDetents([.height(344)])
            .presentationDragIndicator(.hidden)
        case .live:
            quickScreen(LiveView())
        case .workout:
            quickScreen(WorkoutsView())
        case .journal:
            quickScreen(InsightsView())
        case .breathe:
            quickScreen(BreathingView())
        }
    }

    /// Wraps a routed quick-action screen in its own nav stack so it has a title bar + the
    /// shared surface background, matching how the Profile rows present these same views.
    private func quickScreen<V: View>(_ view: V) -> some View {
        NavigationStack {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: these screens draw a full-bleed liquid sky (ScreenScaffold topBackground) that runs
                // edge-to-edge under a transparent bar — exactly how the tab roots present it. An OPAQUE
                // surfaceBase toolbar background sat on top of that sky and, as the content scrolled up, its
                // extended status-bar band CLIPPED the sky + the in-content header ("Live Body Console").
                // Hiding the bar background lets the sky stay continuous under the floating Done button.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { quickAction = nil }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    /// The Devices manager wrapped in its own nav stack + Done button (mirrors `quickScreen`, but
    /// dismisses the dedicated `showDevices` sheet rather than the quick-action item).
    private var devicesScreen: some View {
        NavigationStack {
            DevicesView()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: same fix as quickScreen — Devices draws the full-bleed liquid sky, so a transparent
                // nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDevices = false }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    /// One primary tab's stack, bound to `tabPaths[tag]` and scroll token `scrollTop[tag]`.
    private func tabStack<V: View>(_ view: V, tag: Int, profileInToolbar: Bool) -> some View {
        // Each primary tab gets its OWN NavigationStack so the in-content NavigationLinks (e.g. the Today
        // dashboard card rows) both navigate AND render opaque. An ORPHANED NavigationLink (no
        // NavigationStack ancestor) renders its whole label in a disabled/translucent state — that was
        // washing the Today cards over the hero scene and dimming their text to grey (2026-06-23).
        // Each screen draws its own in-content header; pushed detail screens get their own nav bar + back
        // button. The stack is bound to the tab's path so a re-tap of the active tab can pop it to the
        // root (#135/#198); the roots' first-hop links push TabRoute / MoreDestination values, each
        // registered here ONCE per stack (a double registration double-pushes, #38).
        NavigationStack(path: $tabPaths[tag]) {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .modifier(TabRootChrome(profileInToolbar: profileInToolbar, openProfile: openProfile))
                .tabRouteDestinations()
                .moreDestinations()
        }
        // Drive this tab's root scroll-to-top on an at-root re-tap (#198 follow-up); read by ScreenScaffold
        // / LiquidTodayView inside. Only THIS tab's token changes on its reselect, so the others don't scroll.
        .environment(\.scrollToTopSignal, scrollTop[tag])
    }
}

/// Literal tab tags. `tabPaths` and `scrollTop` are indexed by these, and they never renumber when Coach
/// is switched off: Coach is the last tag, so removing it cannot shift any other tab's path or scroll.
private enum TabTag {
    static let today = 0
    static let sleep = 1
    static let training = 2
    static let health = 3
    static let coach = 4
    /// The four always-present tabs, in bar order (the tab-swipe walks these, plus Coach when enabled).
    static let primary = [today, sleep, training, health]
    static let count = 5
}

/// A tab root's navigation-bar chrome. `profileInToolbar` is fixed per tab for the life of the view, so
/// the branch below never flips identity at runtime.
///
/// Without the avatar, the bar stays hidden: the root draws its own in-content header (Today's carries
/// its own avatar). With it, the bar is shown with a hidden background, so the avatar floats at the
/// top-right over the screen's full-bleed backdrop instead of an opaque band.
private struct TabRootChrome: ViewModifier {
    let profileInToolbar: Bool
    let openProfile: () -> Void

    func body(content: Content) -> some View {
        if profileInToolbar {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileAvatarButton(action: openProfile)
                    }
                }
        } else {
            content.toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Quick actions (centre FAB)

/// The destinations the centre FAB can present. `.menu` is the action sheet itself; the rest
/// route to existing screens. `Identifiable` so it drives `.sheet(item:)`.
private enum QuickAction: Int, Identifiable {
    case menu, live, workout, journal, breathe
    var id: Int { rawValue }
}

/// The bottom sheet of quick actions presented by the centre FAB. Spec bottom sheet: surfaceOverlay
/// fill, gold hairline top edge, grab handle, three flat action rows that route to existing screens.
private struct QuickActionSheet: View {
    /// Called with the picked destination (the host swaps the menu for that screen).
    let onPick: (QuickAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grab handle (36×4) in the slate hairline tone.
            Capsule()
                .fill(StrandPalette.hairlineStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("QUICK ACTIONS")
                .font(StrandFont.overline)
                .tracking(1.6)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                row("Live HR", icon: "waveform.path.ecg", tint: StrandPalette.metricRose) { onPick(.live) }
                row("Start workout", icon: "figure.run", tint: StrandPalette.effortColor) { onPick(.workout) }
                row("Log journal", icon: "square.and.pencil", tint: StrandPalette.accent) { onPick(.journal) }
                row("Breathe", icon: "wind", tint: StrandPalette.restColor) { onPick(.breathe) }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            NoopChromeSurface()
                .overlay(alignment: .top) {
                    // Gold hairline top edge per the bottom-sheet spec.
                    Rectangle()
                        .fill(StrandPalette.gold.opacity(0.35))
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }

    /// One flat action row: hued line-icon tile + title, inset surface, hairline border.
    private func row(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(StrandPalette.surfaceInset))
                Text(title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(NoopPanelSurface(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#endif

/// #1841: apply the iOS 26 tab-bar minimise behaviour, doing nothing on older systems.
///
/// The availability branch is deliberately the ONLY branch. `RootTabView` already documents what happens
/// when a condition that flips at runtime wraps this `TabView`: #519 put two states in separate
/// `_ConditionalContent` branches, and every navigation rebuilt the whole subtree, resetting `@State`
/// inside the tab roots — scroll offsets, chart ranges, expanded sections.
///
/// So the preference must NOT select between branches. It selects the modifier's ARGUMENT, while the
/// availability check — fixed for the life of the process — is what picks a branch. Toggling the setting
/// changes a value, never the view's identity.
extension View {
    @ViewBuilder
    func noopTabBarAutoHide(_ enabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            // `.onScrollDown` minimises to a pill on downward scroll; `.never` pins it fully visible.
            self.tabBarMinimizeBehavior(enabled ? .onScrollDown : .never)
        } else {
            self
        }
    }
}
