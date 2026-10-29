#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The Training tab root (redesign round 2 "04 Training"), structural version. It links to the existing
/// screens rather than re-implementing them: Workouts and Lift Log push `MoreDestination` values onto the
/// tab's bound path (so a re-tap of the tab pops them), a recent session opens the existing
/// `WorkoutDetailView` exactly as the Workouts list presents it, and "Paste a workout" opens the existing
/// preview-before-save `WorkoutTextImportSheet`. Phase 5 adds the rings, consistency calendar and source
/// labels; nothing here computes a new value.
struct TrainingHubView: View {
    @EnvironmentObject private var repo: Repository

    @State private var recent: [WorkoutRow] = []
    @State private var loaded = false
    @State private var detail: DetailTarget?
    @State private var pastingWorkout = false

    /// Wraps a tapped row so `.sheet(item:)` can present its detail (mirrors `WorkoutsView`).
    private struct DetailTarget: Identifiable {
        let row: WorkoutRow
        let id = UUID()
    }

    var body: some View {
        ScreenScaffold(title: nil, onRefresh: { await repo.refresh() }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Training")
                    .noopFont(.largeTitle)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    hubLink(Text("Workouts"), subtitle: Text("Every session, threaded together."),
                            icon: "figure.run", tint: NoopTheme.strain, route: .workouts, divider: true)
                    hubLink(Text("Lift Log"), subtitle: nil,
                            icon: "dumbbell.fill", tint: NoopTheme.lift, route: .liftLog, divider: false)
                }
                .trainingCardSurface()
                .padding(.top, NoopTheme.Layout.l)

                Text("Recent")
                    .noopFont(.sectionTitle)
                    .padding(.top, NoopTheme.Layout.sectionTop)
                    .padding(.bottom, NoopTheme.Layout.sectionBottom)
                    .accessibilityAddTraits(.isHeader)
                recentCard

                Button { pastingWorkout = true } label: {
                    rowContent(title: Text("Paste a workout"), subtitle: Text("Preview before it saves"),
                               icon: "doc.on.clipboard", tint: NoopTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .trainingCardSurface()
                .padding(.top, NoopTheme.Layout.cardGap)
            }
        }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(item: $detail) { target in
            NavigationStack {
                WorkoutDetailView(row: target.row)
                    .environmentObject(repo)
            }
            .noopSheetPresentation(largeFirst: true)
        }
        .sheet(isPresented: $pastingWorkout) {
            WorkoutTextImportSheet { await repo.refresh(); await load() }
        }
    }

    /// The five newest sessions from the same read the Workouts screen uses, bounded to 30 days.
    private func load() async {
        recent = Array(await repo.workoutRows(days: 30).prefix(5))
        loaded = true
    }

    @ViewBuilder private var recentCard: some View {
        if recent.isEmpty {
            Text(loaded ? "No workouts yet" : "Loading your sessions…")
                .noopFont(.bodySmall)
                .foregroundStyle(NoopTheme.textSecondary)
                .padding(.horizontal, NoopTheme.Layout.l)
                .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .trainingCardSurface()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.offset) { index, row in
                    Button { detail = DetailTarget(row: row) } label: {
                        // Sport names and dates are data, never catalogue keys.
                        rowContent(title: Text(verbatim: WorkoutSource.displaySport(row.sport)),
                                   subtitle: Text(verbatim: sessionSubtitle(row)),
                                   icon: WorkoutTypeIconography.systemSymbolName(for: row.sport),
                                   tint: NoopTheme.strain,
                                   divider: index < recent.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .trainingCardSurface()
        }
    }

    /// "29 Oct 2026 at 07:10 · 52 min". The duration is omitted when the row carries none.
    private func sessionSubtitle(_ row: WorkoutRow) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(row.startTs))
        var parts = [start.formatted(date: .abbreviated, time: .shortened)]
        if let seconds = row.durationS, seconds >= 60 {
            parts.append(String(localized: "\(Int((seconds / 60).rounded())) min"))
        }
        return parts.joined(separator: " · ")
    }

    private func hubLink(_ title: Text, subtitle: Text?, icon: String,
                         tint: Color, route: MoreDestination, divider: Bool) -> some View {
        NavigationLink(value: route) {
            rowContent(title: title, subtitle: subtitle, icon: icon, tint: tint, divider: divider)
        }
        .buttonStyle(.plain)
    }

    /// One list row: domain icon tile, title, optional sub-line, chevron.
    private func rowContent(title: Text, subtitle: Text?,
                            icon: String, tint: Color, divider: Bool = false) -> some View {
        HStack(spacing: NoopTheme.Layout.m) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: NoopTheme.Layout.iconTile, height: NoopTheme.Layout.iconTile)
                .background(
                    RoundedRectangle(cornerRadius: NoopTheme.Layout.iconTileRadius, style: .continuous)
                        .fill(tint.opacity(0.14))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.noopFont(.rowTitle)
                if let subtitle {
                    subtitle.noopFont(.footnote)
                }
            }
            Spacer(minLength: NoopTheme.Layout.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NoopTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, NoopTheme.Layout.l)
        .padding(.vertical, NoopTheme.Layout.m)
        .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle()
                    .fill(NoopTheme.separator)
                    .frame(height: 1)
                    .padding(.leading, NoopTheme.Layout.l + NoopTheme.Layout.iconTile + NoopTheme.Layout.m)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// The redesign card: translucent fill plus a 1 pt hairline, at the card radius.
    func trainingCardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous)
        return self
            .background(shape.fill(NoopTheme.card))
            .overlay(shape.strokeBorder(NoopTheme.cardBorder, lineWidth: 1))
            .clipShape(shape)
    }
}

#endif
