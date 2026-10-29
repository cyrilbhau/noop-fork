import SwiftUI
import StrandDesign

/// Shared Shown / Hidden list used by Today sections, Key Metrics, and Your Cards.
struct EditableLayoutList<Item, Options>: View
where Item: Identifiable & Equatable, Options: View {
    @Binding var draft: EditableLayoutDraft<Item>

    let shownTitle: String
    let hiddenTitle: String
    let title: (Item) -> String
    let subtitle: (Item) -> String?
    let icon: (Item) -> String
    let tint: (Item) -> Color
    let configurationLabel: (Item) -> String?
    let onConfigure: (Item) -> Void
    let onReset: () -> Void
    /// Whether the final Shown row offers its hide action. Actual removal also requires
    /// `permitsEmptyDraft`, preserving the existing behavior outside the redesigned Today editor.
    var allowEmpty: Bool = false
    // Only the redesigned Added Cards page opts into removing the final item.
    var permitsEmptyDraft: Bool = false
    var header: AnyView? = nil
    var extraFooter: AnyView? = nil
    var subtitleTint: ((Item) -> Color?)? = nil
    var wrapsSubtitles: Bool = false
    /// Optional grouping key for the Hidden ("Available") list. When set (the hosted-cards page passes the
    /// card's origin, e.g. "Sleep" / "Trends"), the Available items are split into one titled Section per
    /// group so a user browses by origin instead of one flat list. nil (Today sections, Key Metrics, Your
    /// Cards) keeps the single flat Available section. The Shown list stays flat — it is the user's own
    /// cross-origin order.
    var group: ((Item) -> String)? = nil
    @ViewBuilder let options: () -> Options

    var body: some View {
        List {
            if let header { header }
            options()

            Section {
                ForEach(draft.visible) { item in
                    EditableLayoutRow(
                        title: title(item),
                        subtitle: subtitle(item),
                        subtitleTint: subtitleTint?(item),
                        wrapsSubtitle: wrapsSubtitles,
                        icon: icon(item),
                        tint: tint(item),
                        configurationLabel: configurationLabel(item),
                        isVisible: true,
                        canHide: draft.visible.count > (allowEmpty ? 0 : 1),
                        onConfigure: { onConfigure(item) },
                        onVisibilityChange: { hide(item) }
                    )
                }
                .onMove(perform: moveVisible)
            } header: {
                Text(shownTitle)
                    .strandOverline()
            } footer: {
                if let extraFooter {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                        Text("Drag to reorder. Move an item to Hidden to remove it from Today without deleting it.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                        extraFooter
                    }
                } else {
                    Text("Drag to reorder. Move an item to Hidden to remove it from Today without deleting it.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }

            if draft.hidden.isEmpty {
                Section {
                    Text("Nothing hidden")
                        .foregroundStyle(StrandPalette.textTertiary)
                } header: {
                    Text(hiddenTitle)
                        .strandOverline()
                } footer: {
                    Text("Hidden items remain available here and can be restored at any time.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            } else if group != nil {
                // Grouped Available list: one titled Section per origin (e.g. "Sleep", "Trends"), so the
                // hidden cards read by category. The last group carries the shared restore-hint footer.
                let groups = groupedHidden
                ForEach(groups.indices, id: \.self) { i in
                    Section {
                        ForEach(groups[i].items) { item in hiddenRow(item) }
                    } header: {
                        Text(groups[i].name)
                            .strandOverline()
                    } footer: {
                        if i == groups.count - 1 {
                            Text("Hidden items remain available here and can be restored at any time.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(draft.hidden) { item in hiddenRow(item) }
                } header: {
                    Text(hiddenTitle)
                        .strandOverline()
                } footer: {
                    Text("Hidden items remain available here and can be restored at any time.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }

            Section {
                Button("Reset This Layout", role: .destructive, action: onReset)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .accessibilityLabel("Reset This Layout")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(StrandPalette.surfaceBase)
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
    }

    /// One Available (hidden) row — the show affordance. Shared by the flat and grouped Available lists.
    @ViewBuilder
    private func hiddenRow(_ item: Item) -> some View {
        EditableLayoutRow(
            title: title(item),
            subtitle: subtitle(item),
            subtitleTint: subtitleTint?(item),
            wrapsSubtitle: wrapsSubtitles,
            icon: icon(item),
            tint: tint(item),
            configurationLabel: configurationLabel(item),
            isVisible: false,
            canHide: true,
            onConfigure: { onConfigure(item) },
            onVisibilityChange: { show(item) }
        )
    }

    /// The hidden items bucketed by `group`, groups in first-appearance order (which follows the draft's
    /// canonical order). Only read when `group != nil`.
    private var groupedHidden: [(name: String, items: [Item])] {
        guard let group else { return [] }
        var order: [String] = []
        var buckets: [String: [Item]] = [:]
        for item in draft.hidden {
            let key = group(item)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { (name: $0, items: buckets[$0] ?? []) }
    }

    private func moveVisible(from offsets: IndexSet, to destination: Int) {
        draft.moveVisible(from: offsets, to: destination)
    }

    private func hide(_ item: Item) {
        withAnimation(StrandMotion.interactive) {
            draft.hide(item, allowEmpty: allowEmpty && permitsEmptyDraft)
        }
    }

    private func show(_ item: Item) {
        withAnimation(StrandMotion.interactive) {
            draft.show(item)
        }
    }
}

private struct EditableLayoutRow: View {
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    let title: String
    let subtitle: String?
    let subtitleTint: Color?
    let wrapsSubtitle: Bool
    let icon: String
    let tint: Color
    let configurationLabel: String?
    let isVisible: Bool
    let canHide: Bool
    let onConfigure: () -> Void
    let onVisibilityChange: () -> Void

    var body: some View {
        #if os(iOS)
        if wrapsSubtitle && dynamicTypeSize.isAccessibilitySize {
            accessibilityRow
        } else {
            horizontalRow
        }
        #else
        horizontalRow
        #endif
    }

    private var horizontalRow: some View {
        HStack(spacing: NoopMetrics.space3) {
            RoundedRectangle(cornerRadius: NoopMetrics.space2, style: .continuous)
                .fill(StrandPalette.surfaceInset)
                .frame(width: NoopMetrics.space8, height: NoopMetrics.space8)
                .overlay {
                    Image(systemName: icon)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(isVisible ? tint : StrandPalette.textTertiary)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(isVisible ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                if let subtitle {
                    Text(subtitle)
                        .font(StrandFont.caption)
                        .foregroundStyle(subtitleTint ?? StrandPalette.textTertiary)
                        .lineLimit(wrapsSubtitle ? nil : 1)
                }
            }

            Spacer(minLength: NoopMetrics.space2)

            if let configurationLabel {
                Button(configurationLabel, action: onConfigure)
                    .buttonStyle(.plain)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityLabel(String(localized: "Edit \(title)"))
            }

            Button(action: onVisibilityChange) {
                Image(systemName: isVisible ? "minus.circle.fill" : "plus.circle.fill")
                    .font(StrandFont.title2)
                    .foregroundStyle(isVisible ? StrandPalette.textSecondary : StrandPalette.accent)
            }
            .buttonStyle(.plain)
            .disabled(isVisible && !canHide)
            .accessibilityLabel(visibilityLabel)
        }
        .contentShape(Rectangle())
        .listRowBackground(NoopChromeSurface())
    }

    #if os(iOS)
    private var accessibilityRow: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(title)
                    .noopFont(.listTitle, color: false)
                    .foregroundStyle(isVisible ? NoopTheme.textPrimary : NoopTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(subtitleTint ?? NoopTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: NoopTheme.Layout.s) {
                Image(systemName: icon)
                    .noopFont(.footnote, color: false)
                    .foregroundStyle(isVisible ? tint : NoopTheme.textTertiary)
                    .frame(minWidth: NoopTheme.Layout.minTouchTarget, minHeight: NoopTheme.Layout.minTouchTarget)
                    .accessibilityHidden(true)
                Spacer(minLength: NoopTheme.Layout.s)
                if let configurationLabel {
                    Button(configurationLabel, action: onConfigure)
                        .buttonStyle(.plain)
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(NoopTheme.strain)
                        .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                        .accessibilityLabel(String(localized: "Edit \(title)"))
                }
                Button(action: onVisibilityChange) {
                    Image(systemName: isVisible ? "minus.circle.fill" : "plus.circle.fill")
                        .noopFont(.sectionTitle, color: false)
                        .foregroundStyle(isVisible ? NoopTheme.textSecondary : NoopTheme.strain)
                        .frame(minWidth: NoopTheme.Layout.minTouchTarget, minHeight: NoopTheme.Layout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isVisible && !canHide)
                .accessibilityLabel(visibilityLabel)
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(NoopChromeSurface())
    }
    #endif

    private var visibilityLabel: String {
        isVisible
            ? String(localized: "Hide \(title)")
            : String(localized: "Show \(title)")
    }

}
