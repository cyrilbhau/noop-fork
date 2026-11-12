import SwiftUI
import UIKit
import UniformTypeIdentifiers
import StrandAnalytics
import StrandDesign

// Stage 5 (events layer), specification §10.1, §10.2 and §10.4, frames H and L of
// `design/round-s5-events/`. The Events screen lists the owner's personal events newest start
// first in three sections, Now, Upcoming and Earlier, and is the one screen where a private event
// shows its own name and note. Rows are neutral: an event has no colour.
//
// The screen draws `PersonalEventsModel` and decides nothing: every word, date and section is the
// presenter's, and every write goes through the model.

/// The Events screen, pushed from the Health tab's row and the scorecard's event note. Leaves the
/// stack when the feature is switched off.
struct PersonalEventsView: View {
    @StateObject private var model: PersonalEventsModel
    @ObservedObject private var flag = PersonalEventStore.flag
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private let store: PersonalEventStore
    /// The loading skeleton (frame L6). The model reads synchronously, so only the demo shows it.
    private let isLoading: Bool
    @State private var sheet: SheetTarget?
    @State private var pendingDelete: PendingDelete?
    @State private var asksStartAgain = false
    @State private var failedWrite = false

    /// Every parameter is for the debug demo, which opens the screen in a given state; the app uses
    /// the shared store and the defaults.
    init(store: PersonalEventStore? = nil, model: PersonalEventsModel? = nil, isLoading: Bool = false,
         opensSheet: SheetTarget? = nil, asksDelete: String? = nil, asksStartAgain: Bool = false) {
        let store = store ?? .shared
        let shown = model ?? PersonalEventsModel(store: store, pasteboard: SystemPersonalEventStoredTextPasteboard())
        self.store = store
        self.isLoading = isLoading
        _model = StateObject(wrappedValue: shown)
        _sheet = State(initialValue: opensSheet)
        _pendingDelete = State(initialValue: asksDelete.flatMap { id in
            shown.deleteConfirmation(id: id).map { PendingDelete(id: id, confirmation: $0) }
        })
        _asksStartAgain = State(initialValue: asksStartAgain)
    }

    /// What the add-or-edit sheet is open for.
    enum SheetTarget: Identifiable, Equatable {
        case new
        case edit(PersonalEvent)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let event): return event.id
            }
        }
    }

    private struct PendingDelete: Identifiable {
        let id: String
        let confirmation: PersonalEventDeleteConfirmation
    }

    private var presentation: PersonalEventsPresentation { model.presentation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    loading
                } else {
                    switch presentation.state {
                    case .storeUnreadable: storeUnreadable
                    case .empty: empty
                    case .rows: sections
                    }
                }
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text("Events"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .new } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add event"))
                .disabled(presentation.state == .storeUnreadable)
            }
        }
        .sheet(item: $sheet) { target in
            PersonalEventSheet(model: sheetModel(for: target), onDelete: { id in
                sheet = nil
                requestDelete(id)
            })
        }
        .confirmationDialog(Text(verbatim: pendingDelete?.confirmation.title ?? ""),
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { pending in
            Button(role: .destructive) {
                do { try model.delete(pending.id) } catch { failedWrite = true }
            } label: { Text(verbatim: pending.confirmation.confirmTitle) }
            Button(role: .cancel) {} label: { Text(verbatim: pending.confirmation.cancelTitle) }
        } message: { pending in
            Text(verbatim: pending.confirmation.detail + "\n" + pending.confirmation.warning)
        }
        .confirmationDialog(Text("Start again and discard the stored events?"), isPresented: $asksStartAgain,
                            titleVisibility: .visible) {
            Button(role: .destructive) { model.discardUnreadableStore() } label: { Text("Start again") }
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("This cannot be undone.")
        }
        .alert(Text("Could not save. Try again."), isPresented: $failedWrite) {
            Button(role: .cancel) {} label: { Text("OK") }
        }
        .onChangeCompat(of: flag.isEnabled) { enabled in
            if !enabled { dismiss() }
        }
        // The day may have changed while the app was suspended; the model takes "today" again.
        .onChangeCompat(of: scenePhase) { phase in
            if phase == .active { model.reload() }
        }
    }

    private func sheetModel(for target: SheetTarget) -> PersonalEventSheetModel {
        switch target {
        case .new: return PersonalEventSheetModel(store: store)
        case .edit(let event): return PersonalEventSheetModel(store: store, editing: event)
        }
    }

    private func requestDelete(_ id: String) {
        guard let confirmation = model.deleteConfirmation(id: id) else { return }
        pendingDelete = PendingDelete(id: id, confirmation: confirmation)
    }

    private func edit(_ id: String) {
        guard let event = model.event(id: id) else { return }
        sheet = .edit(event)
    }

    // MARK: Rows

    @ViewBuilder
    private var sections: some View {
        section(Text("Now"), presentation.now, first: true)
        section(Text("Upcoming"), presentation.upcoming, first: presentation.now.isEmpty)
        section(Text("Earlier"), presentation.earlier,
                first: presentation.now.isEmpty && presentation.upcoming.isEmpty)
        if let unreadable = presentation.unreadableEntriesText {
            FormKitFootnote(verbatim: unreadable)
        }
    }

    @ViewBuilder
    private func section(_ title: Text, _ rows: [PersonalEventRow], first: Bool) -> some View {
        if !rows.isEmpty {
            title
                .noopFont(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, first ? NoopTheme.Layout.l : NoopTheme.Layout.sectionTop)
                .padding(.bottom, NoopTheme.Layout.sectionBottom)
                .padding(.horizontal, NoopTheme.Layout.sectionSide)
            FormKitCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    PersonalEventRowView(row: row, showsDivider: index > 0,
                                         onEndToday: { endToday(row.id) })
                        .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
                        .contentShape(Rectangle())
                        .onTapGesture { edit(row.id) }
                        .accessibilityAddTraits(.isButton)
                        .contextMenu {
                            Button { edit(row.id) } label: { Label { Text("Edit") } icon: { Image(systemName: "pencil") } }
                            Button(role: .destructive) { requestDelete(row.id) } label: {
                                Label { Text("Delete") } icon: { Image(systemName: "trash") }
                            }
                        }
                }
            }
        }
    }

    private func endToday(_ id: String) {
        do { try model.endToday(id: id) } catch { failedWrite = true }
    }

    // MARK: States

    private var empty: some View {
        NoopGlassCard {
            VStack(spacing: NoopTheme.Layout.m) {
                Image(systemName: "calendar")
                    .font(.system(size: PersonalEventsLayout.emptyIcon))
                    .foregroundStyle(NoopTheme.textSecondary)
                    .accessibilityHidden(true)
                Text("No events yet")
                    .noopFont(.rowTitle)
                    .multilineTextAlignment(.center)
                Text("Add travel, illness, a diet break or a deload, and charts will show when it happened.")
                    .noopFont(.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { sheet = .new } label: { Text("Add event") }
                    .buttonStyle(NoopPrimaryButtonStyle())
                    .padding(.top, NoopTheme.Layout.s)
            }
            .frame(maxWidth: .infinity)
        }
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.sectionTop)
    }

    private var storeUnreadable: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                Text("Your events could not be read")
                    .noopFont(.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing has been changed. You can copy the stored text before starting again.")
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Button { model.copyStoredText() } label: { Text("Copy stored text") }
                    .buttonStyle(NoopSecondaryButtonStyle())
                    .disabled(model.rawStoredText == nil)
                Button { asksStartAgain = true } label: { Text("Start again") }
                    .buttonStyle(NoopSecondaryButtonStyle())
            }
        }
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.sectionTop)
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: " ")
                .noopFont(.sectionTitle)
                .padding(.top, NoopTheme.Layout.l)
                .padding(.bottom, NoopTheme.Layout.sectionBottom)
                .padding(.horizontal, NoopTheme.Layout.sectionSide)
            FormKitCard {
                ForEach(0..<PersonalEventsLayout.skeletonRows, id: \.self) { index in
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                        Text(verbatim: " ").noopFont(.listTitle)
                        Text(verbatim: " ").noopFont(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, FormKitLayout.rowVertical)
                    .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
                    .overlay(alignment: .top) { if index > 0 { FormKitDivider() } }
                }
            }
            .noopSkeleton(true)
        }
        .accessibilityHidden(true)
    }
}

/// Measures of the Events screen with no token of their own.
enum PersonalEventsLayout {
    /// The calendar symbol above the empty state's title.
    static let emptyIcon: CGFloat = 36
    /// Skeleton rows while the list loads (frame L6).
    static let skeletonRows = 5
}

/// One event: its name with the Private tag, the note's first line, the dates, and End today for an
/// ongoing event that has started. At accessibility sizes the dates stack under the name and the
/// tag wraps below it.
private struct PersonalEventRowView: View {
    let row: PersonalEventRow
    let showsDivider: Bool
    let onEndToday: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { FormKitDivider() }
            let layout = stacks
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.s))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.m))
            layout {
                VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                    title
                    if let note = row.noteFirstLine {
                        Text(verbatim: note)
                            .noopFont(.footnote)
                            .lineLimit(stacks ? nil : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: stacks ? .leading : .trailing, spacing: NoopTheme.Layout.xs) {
                    FormKitValue(verbatim: row.dateText)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if row.offersEndToday {
                        Button(action: onEndToday) { Text("End today") }
                            .buttonStyle(NoopGhostButtonStyle())
                    }
                }
            }
            .padding(.vertical, FormKitLayout.rowVertical)
            .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var title: some View {
        let name = Text(verbatim: row.title)
            .noopFont(.listTitle)
            .fixedSize(horizontal: false, vertical: true)
        if stacks {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                name
                if row.isPrivate { FormKitBadge("Private", tint: NoopTheme.textSecondary) }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                name
                if row.isPrivate { FormKitBadge("Private", tint: NoopTheme.textSecondary) }
            }
        }
    }
}

/// Writes "Copy stored text" to the general pasteboard as an item that stays on this iPhone and
/// expires, as the coach packet's writer does: `localOnly` keeps the item out of Universal Clipboard
/// and Handoff, and `expirationDate` has the system remove it at the plan's `expiresAt`.
struct SystemPersonalEventStoredTextPasteboard: PersonalEventStoredTextPasteboardWriting {
    func write(_ plan: PersonalEventStoredTextCopyPlan) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: plan.text]],
            options: [.localOnly: plan.localOnly, .expirationDate: plan.expiresAt])
    }
}

/// The Health tab's row label (§10.1): "Events" and the count of events overlapping today, or
/// nothing. Mounted by the Health tab only while the feature is on.
struct PersonalEventsHealthRowLabel: View {
    let showsDivider: Bool
    @StateObject private var model: PersonalEventsModel
    @Environment(\.scenePhase) private var scenePhase

    /// `model` is for the debug demo; the app reads the shared store.
    init(showsDivider: Bool, model: PersonalEventsModel? = nil) {
        self.showsDivider = showsDivider
        _model = StateObject(wrappedValue: model ?? PersonalEventsModel())
    }

    var body: some View {
        NoopListRow("Events", systemImage: "calendar", color: NoopTheme.textPrimary,
                    value: model.presentation.healthRowValue, showsDivider: showsDivider)
            // The day may have changed while the app was suspended; the model takes "today" again.
            .onChangeCompat(of: scenePhase) { phase in
                if phase == .active { model.reload() }
            }
    }
}
