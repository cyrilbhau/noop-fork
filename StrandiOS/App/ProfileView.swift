#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Profile (replaces the More tab)
//
// Redesign D3 (`design/round3/coach-profile.html`). The iPhone shell's catch-all index moved from a fifth
// "More" tab into a sheet behind the avatar at the top-right of each tab. Every row the More list carried
// is still here, pushing the same `MoreDestination` value onto this sheet's own `NavigationStack`, so no
// screen became unreachable in the move (Workouts, Lift Log and Health became the Training and Health
// tabs instead). Phase 7 restyles this screen fully; this is the structural version.

/// The Profile sheet: strap card, grouped destinations, and a Settings gear.
///
/// The path is owned by `RootTabView` so a router request that arrives while the sheet is up (Live's
/// "Manage devices", an Insights deep link) can push onto THIS stack instead of trying to present a second
/// sheet over it, which SwiftUI refuses.
struct ProfileSheet: View {
    @Binding var path: NavigationPath
    let onClose: () -> Void

    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ProfileStrapCard()
                        .padding(.top, NoopTheme.Layout.xl)
                    ForEach(ProfileGroup.all) { group in
                        ProfileGroupView(group: group)
                    }
                }
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.bottom, NoopTheme.Layout.xl)
            }
            .background(NoopTheme.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(MoreDestination.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            // Pushed screens can push their own `TabRoute` values (Trends' small multiples, the metric
            // explorer), so this stack registers both route types, once each.
            .tabRouteDestinations()
            .moreDestinations()
        }
    }

    private var header: some View {
        HStack(spacing: NoopTheme.Layout.l) {
            ProfileAvatarView(imageData: profile.avatarImageData, size: profileAvatarSize)
            Text("Profile")
                .noopFont(.largeTitle)
            Spacer(minLength: 0)
        }
        .padding(.top, NoopTheme.Layout.s)
    }
}

/// Diameter of the header avatar in the Profile sheet (D3: 68 pt).
private let profileAvatarSize: CGFloat = 68
/// Small icon tile used by list rows (the mockup's `icon sm`).
private let profileRowIconSize: CGFloat = 30
private let profileRowIconRadius: CGFloat = 8

// MARK: - Groups

/// One row in the Profile index: a title, an SF Symbol, its domain tint and the screen it pushes.
private struct ProfileItem: Identifiable {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
    let route: MoreDestination
    var id: MoreDestination { route }

    init(_ title: LocalizedStringKey, _ icon: String, _ tint: Color, _ route: MoreDestination) {
        self.title = title; self.icon = icon; self.tint = tint; self.route = route
    }
}

/// A titled group of Profile rows. Order and membership follow REDESIGN-IMPLEMENTATION.md Phase 2.
private struct ProfileGroup: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let items: [ProfileItem]

    static let all: [ProfileGroup] = [
        ProfileGroup(id: "data", title: "Your data", items: [
            ProfileItem("Data sources", "externaldrive.fill", NoopTheme.hrv, .dataSources),
            ProfileItem("Apple Health", "heart.fill", NoopTheme.heart, .appleHealth),
            ProfileItem("Backup & Sync", "externaldrive.fill.badge.icloud", NoopTheme.recovery, .backupSync),
        ]),
        ProfileGroup(id: "tools", title: "Tools", items: [
            ProfileItem("Alarms", "alarm.fill", NoopTheme.sleep, .alarms),
            ProfileItem("Breathe", "wind", NoopTheme.breath, .breathe),
            ProfileItem("Stress", "bolt.heart.fill", NoopTheme.stress, .stress),
            // The journal lives on the Insights screen (`InsightsView` hosts `JournalLogCard`); it is the
            // same screen the "Log journal" quick action opens.
            ProfileItem("Journal", "book.fill", NoopTheme.sleep, .insights),
            ProfileItem("Intervals", "timer", NoopTheme.strain, .intervals),
            ProfileItem("Live", "waveform.path.ecg", NoopTheme.heart, .live),
        ]),
        ProfileGroup(id: "insights", title: "Insights", items: [
            ProfileItem("What moves you", "wand.and.sparkles", NoopTheme.recovery, .insightsHub),
            ProfileItem("Trends", "chart.line.uptrend.xyaxis", NoopTheme.hrv, .trends),
            ProfileItem("All metrics", "square.grid.2x2.fill", NoopTheme.textPrimary, .explore),
            ProfileItem("Intelligence", "brain.head.profile", NoopTheme.coach, .intelligence),
            ProfileItem("Compare", "rectangle.split.2x1.fill", NoopTheme.strain, .compare),
            ProfileItem("Lab Book", "books.vertical.fill", NoopTheme.temp, .labBook),
        ]),
        ProfileGroup(id: "more", title: "More tools", items: [
            // Experimental beat-to-beat regularity visualization; self-gates on its own consent.
            ProfileItem("Rhythm", "waveform.path", NoopTheme.textSecondary, .rhythm),
            ProfileItem("Your Data, Fused", "square.stack.3d.up.fill", NoopTheme.textSecondary, .fusedRecord),
            ProfileItem("Mi Band", "figure.walk.motion", NoopTheme.textSecondary, .miBand),
            // #155: HealthKit-free Apple Health path for sideloaded installs.
            ProfileItem("Shortcuts Export", "square.and.arrow.up.fill", NoopTheme.textSecondary, .shortcutsExport),
            // The plain 4.0 vs 5.0/MG capability grid: what NOOP reads live off each strap.
            ProfileItem("NOOP Limitations", "list.bullet.rectangle", NoopTheme.textSecondary, .noopLimitations),
            ProfileItem("Automations", "wand.and.stars", NoopTheme.textSecondary, .automations),
            // The diagnostics and bug-report hub keeps a first-class row, not just a Settings entry.
            ProfileItem("Test Centre", "stethoscope", NoopTheme.textSecondary, .testCentre),
            ProfileItem("Siri & Shortcuts", "mic.fill", NoopTheme.textSecondary, .siriShortcuts),
            // #477: the strap-battery levers people reach for when a strap is running down.
            ProfileItem("Power saving", "battery.25", NoopTheme.textSecondary, .powerSaving),
        ]),
    ]
}

private struct ProfileGroupView: View {
    let group: ProfileGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .noopFont(.sectionTitle)
                .padding(.horizontal, NoopTheme.Layout.sectionSide - NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.sectionTop)
                .padding(.bottom, NoopTheme.Layout.sectionBottom)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    ProfileRow(item: item, showsDivider: index < group.items.count - 1)
                }
            }
            .profileCardSurface()
        }
    }
}

private struct ProfileRow: View {
    let item: ProfileItem
    let showsDivider: Bool

    var body: some View {
        NavigationLink(value: item.route) {
            HStack(spacing: NoopTheme.Layout.m) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: profileRowIconSize, height: profileRowIconSize)
                    .background(
                        RoundedRectangle(cornerRadius: profileRowIconRadius, style: .continuous)
                            .fill(item.tint.opacity(0.15))
                    )
                    .accessibilityHidden(true)
                Text(item.title)
                    .noopFont(.listTitle)
                Spacer(minLength: NoopTheme.Layout.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoopTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NoopTheme.Layout.l)
            .padding(.vertical, NoopTheme.Layout.s)
            .frame(minHeight: NoopTheme.Layout.minTouchTarget + NoopTheme.Layout.s)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(NoopTheme.separator)
                        .frame(height: 1)
                        .padding(.leading, NoopTheme.Layout.l + profileRowIconSize + NoopTheme.Layout.m)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Strap card

/// Battery ring and sync state for the active device, at the top of Profile. Display-only: every value is
/// resolved by the same helpers the Today header and the Devices screen already use
/// (`LiquidTodayView.StrapBatteryDisplay.resolve`, `SyncChipState.resolve`), so the card cannot disagree
/// with either. Tap opens Devices.
private struct ProfileStrapCard: View {
    @EnvironmentObject private var live: LiveState

    private var batteryDisplay: LiquidTodayView.StrapBatteryDisplay {
        .resolve(
            activeIsWhoop: live.activeIsWhoop,
            connected: live.connected,
            batteryPct: live.batteryPct,
            charging: live.charging,
            ringPct: live.ouraBatteryPct,
            ringCharging: live.ouraWearState == .charging
        )
    }

    private var indicatorState: ChargeSyncIndicator.BatteryState? {
        switch batteryDisplay {
        case .notActiveDevice: return nil
        case .offline: return .offline
        case .pending(let charging): return .pending(charging: charging)
        case .charge(let percent, let charging, _): return .charge(percent: percent, charging: charging)
        }
    }

    /// The second line: sync progress or age when known, otherwise the link state. Reuses the Devices
    /// screen's strings so the two surfaces read identically.
    private var detail: String {
        switch SyncChipState.resolve(live: live) {
        case .syncing(let chunks, _):
            return chunks > 0 ? String(localized: "Syncing… \(chunks) chunks") : String(localized: "Syncing…")
        case .synced(let agoText):
            return String(localized: "Synced \(agoText) ago")
        case .experimentalLive:
            return String(localized: "Connected; strap history sync is experimental on this strap")
        case .hidden:
            return live.connected ? String(localized: "Connected") : String(localized: "Not connected")
        }
    }

    /// VoiceOver reading of the ring, which is hidden from accessibility itself. Same strings, and the
    /// same "never a strap's number under a ring" rule, as the Today header's battery button.
    private var batteryAccessibility: String? {
        switch batteryDisplay {
        case .notActiveDevice:
            return nil
        case .offline:
            return String(localized: "Strap battery, strap not connected")
        case .pending(let charging):
            return charging
                ? String(localized: "Strap battery charging, no reading yet")
                : String(localized: "Strap battery, no reading yet")
        case .charge(let percent, let charging, let isRing):
            let n = Int(percent.rounded())
            if isRing {
                return charging
                    ? String(localized: "Ring battery \(n) percent, charging")
                    : String(localized: "Ring battery \(n) percent")
            }
            return charging
                ? String(localized: "Strap battery \(n) percent, charging")
                : String(localized: "Strap battery \(n) percent")
        }
    }

    private var chargingSuffix: String? {
        if case .charge(_, true, _) = batteryDisplay { return String(localized: "Charging") }
        if case .pending(true) = batteryDisplay { return String(localized: "Charging") }
        return nil
    }

    var body: some View {
        NavigationLink(value: MoreDestination.devices) {
            HStack(spacing: NoopTheme.Layout.m) {
                if let indicatorState {
                    ChargeSyncIndicator(
                        batteryState: indicatorState,
                        syncing: live.backfilling,
                        chunks: live.syncChunksThisSession
                    )
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Devices")
                        .noopFont(.listTitle)
                    Text([detail, chargingSuffix].compactMap { $0 }.joined(separator: " · "))
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NoopTheme.Layout.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoopTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NoopTheme.Layout.l)
            .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
            .contentShape(Rectangle())
            .profileCardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: batteryAccessibility ?? ""))
    }
}

private extension View {
    /// The redesign card: translucent fill plus a 1 pt hairline, at the card radius.
    func profileCardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous)
        return self
            .background(shape.fill(NoopTheme.card))
            .overlay(shape.strokeBorder(NoopTheme.cardBorder, lineWidth: 1))
            .clipShape(shape)
    }
}

// MARK: - Destinations

/// Every screen the Profile index (formerly the More tab) links to, as a `Hashable` value a
/// `NavigationPath` can carry (#198): a closure-destination push would bypass the path and be
/// un-poppable. The per-screen chrome lives at the single `moreDestinations()` registration.
///
/// `.trends` joined when Trends stopped being a tab, and `.devices` when the Profile strap card started
/// opening Devices in place (the shell's Devices sheet cannot present over the Profile sheet).
enum MoreDestination: Hashable {
    case insightsHub, intelligence, coach, insights, explore, compare, trends
    case live, workouts, liftLog, health, labBook, stress, breathe, intervals, rhythm
    case fusedRecord, appleHealth, miBand, dataSources, backupSync, shortcutsExport, noopLimitations
    case alarms, automations, testCentre, siriShortcuts, powerSaving, settings, devices

    @ViewBuilder var destination: some View {
        switch self {
        case .insightsHub:     InsightsHubView()
        case .intelligence:    IntelligenceView()
        case .coach:           CoachView()
        case .insights:        InsightsView()
        case .explore:         MetricExplorerView()
        case .compare:         CompareView()
        case .trends:          TrendsView()
        case .live:            LiveView()
        case .workouts:        WorkoutsView()
        case .liftLog:         LiftLogView()
        case .health:          HealthView()
        case .labBook:         LabBookView()
        case .stress:          StressView()
        case .breathe:         BreathingView()
        case .intervals:       IntervalTimerView()
        case .rhythm:          RhythmHost()
        case .fusedRecord:     FusedRecordHost()
        case .appleHealth:     AppleHealthView()
        case .miBand:          XiaomiBandView()
        case .dataSources:     DataSourcesView()
        case .noopLimitations: NoopLimitationsView()
        case .backupSync:      BackupSyncView()
        case .shortcutsExport: ShortcutExportSettingsView()
        case .alarms:          SmartAlarmView()
        case .automations:     AutomationsView()
        case .testCentre:      TestCentreView()
        case .siriShortcuts:   SiriShortcutsSettingsView()
        case .powerSaving:     PowerSavingView()
        case .settings:        SettingsView()
        case .devices:         DevicesView()
        }
    }
}

extension View {
    /// Registers `MoreDestination` pushes on the enclosing `NavigationStack`. Apply ONCE per stack (a
    /// double registration double-pushes, #38). Each destination keeps the chrome the More rows applied:
    /// surfaceBase background, inline title, and a hidden bar background so a pushed sky-scaffold screen
    /// keeps its full-bleed sky instead of an opaque band clipping the top on scroll (#1027).
    func moreDestinations() -> some View {
        navigationDestination(for: MoreDestination.self) { route in
            route.destination
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Avatar button

/// The avatar at the top-right of each tab, opening Profile. Uses the photo set in Settings, or the
/// BrandMark fallback `ProfileAvatarView` already draws.
struct ProfileAvatarButton: View {
    let action: () -> Void
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        Button(action: action) {
            ProfileAvatarView(imageData: profile.avatarImageData, size: profileToolbarAvatarSize)
                .frame(width: profileToolbarAvatarSize, height: profileToolbarAvatarSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }
}

/// Toolbar avatar diameter; the toolbar item itself keeps the system's 44 pt hit area.
private let profileToolbarAvatarSize: CGFloat = 32

#endif
