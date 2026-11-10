import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 1 (weigh-in and scorecard), specification §10.5, frames E1 to E4 of
// `design/round6-scorecard/`. Every value the rules use, grouped by rule. First use is prefilled
// with the generic defaults. A value that cannot be saved is marked, its section says why, and Save
// is off.
//
// The sheet holds a `ScorecardPhaseDraft` and decides nothing: the sections, the rows, their units
// and notes, what is invalid and whether Save is allowed are the presenter's and the draft's.

/// The phase and rules sheet, presented from the scorecard. `onSaved` runs after the phase and the
/// rules were stored.
struct ScorecardPhaseSheet: View {
    private let context: ScorecardContext
    private let onSaved: () -> Void
    @State private var draft: ScorecardPhaseDraft
    /// What was typed into each field. A field never typed into shows the draft's own value.
    @State private var typed: [ScorecardPhaseDraft.Field: String] = [:]
    @State private var showsCalendar = false
    @FocusState private var focused: ScorecardPhaseDraft.Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `draft` is for the debug demo, which opens the sheet on a given draft.
    init(context: ScorecardContext, draft: ScorecardPhaseDraft? = nil, onSaved: @escaping () -> Void) {
        self.context = context
        self.onSaved = onSaved
        _draft = State(initialValue: draft
            ?? ScorecardPhaseDraft.current(settings: context.settings, today: context.today))
    }

    private var shown: ScorecardPhaseSheetPresentation {
        let today = context.today
        return CutScorecardPresenter.phaseSheet(
            draft, today: today, previousPhaseName: context.settings.activePhase(on: today)?.name,
            unitSystem: context.unitSystem(), locale: context.locale())
    }

    var body: some View {
        let shown = shown
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.groups.enumerated()), id: \.element.id) { index, group in
                        groupTitle(group.title)
                        if index == 0 {
                            SegmentedPills([CutScorecardStoredPhase.Kind.cut, .other], selection: $draft.kind) { kind in
                                Text(verbatim: kind == .cut ? shown.cutTitle : shown.otherTitle)
                            }
                            .formKitGutter()
                            .padding(.bottom, NoopTheme.Layout.m)
                        }
                        FormKitCard {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { rowIndex, row in
                                rowView(row, showsDivider: rowIndex > 0)
                            }
                        }
                        if let error = group.error {
                            ScorecardFootnote(text: error, color: NoopTheme.recoveryLow)
                        } else if let footnote = group.footnote {
                            ScorecardFootnote(text: footnote, color: NoopTheme.textSecondary)
                        }
                    }
                    if let title = shown.newPhaseTitle {
                        Button {
                            draft = draft.startingNewPhase(today: context.today)
                            typed = [:]
                            focused = nil
                        } label: {
                            Text(verbatim: title)
                        }
                        .buttonStyle(NoopSecondaryButton())
                        .formKitGutter()
                        .padding(.top, NoopTheme.Layout.xl)
                        if let note = shown.newPhaseNote {
                            ScorecardFootnote(text: note, color: NoopTheme.textSecondary)
                        }
                    }
                }
                .padding(.bottom, NoopTheme.Layout.xl)
            }
            .scorecardDemoScroll()
            .scrollDismissesKeyboard(.interactively)
            .background(NoopTheme.sheet.ignoresSafeArea())
            .navigationTitle(Text(verbatim: shown.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(verbatim: shown.cancelTitle) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard draft.save(to: context.settings) else { return }
                        onSaved()
                        dismiss()
                    } label: {
                        Text(verbatim: shown.saveTitle).fontWeight(.semibold)
                    }
                    .disabled(!shown.canSave)
                }
            }
            .tint(NoopTheme.textPrimary)
        }
        .presentationDragIndicator(.visible)
    }

    private func groupTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .noopFont(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopTheme.Layout.gutter + NoopTheme.Layout.captionInset)
            .padding(.top, NoopTheme.Layout.xl)
            .padding(.bottom, NoopTheme.Layout.s)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: ScorecardPhaseRow, showsDivider: Bool) -> some View {
        FormKitControlRow(verbatimTitle: row.label, showsDivider: showsDivider) {
            if row.input == .date {
                Button {
                    focused = nil
                    showsCalendar.toggle()
                } label: {
                    HStack(spacing: NoopTheme.Layout.xs) {
                        valueText(row.text, isInvalid: row.isInvalid)
                        FormKitChevron()
                    }
                    .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.noopPress)
            } else {
                field(row)
            }
        }
        if row.input == .date, showsCalendar {
            DatePicker(selection: startDate, displayedComponents: [.date]) { EmptyView() }
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(NoopTheme.textSecondary)
                .environment(\.calendar, pickerCalendar)
                .environment(\.timeZone, context.timeZone())
                .environment(\.locale, context.locale())
                .padding(.bottom, NoopTheme.Layout.s)
        }
    }

    private func valueText(_ text: String, isInvalid: Bool) -> some View {
        Text(verbatim: text)
            .noopFont(.bodySmall, color: false)
            .foregroundStyle(isInvalid ? NoopTheme.recoveryLow : NoopTheme.textSecondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ row: ScorecardPhaseRow) -> some View {
        let color = row.isInvalid ? NoopTheme.recoveryLow : NoopTheme.textPrimary
        return HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
            TextField(text: text(for: row),
                      prompt: row.placeholder.map { Text(verbatim: $0).foregroundColor(NoopTheme.textTertiary) }) {
                Text(verbatim: row.label)
            }
            .keyboardType(row.input == .text ? .default : row.input == .whole ? .numberPad : .decimalPad)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
            .noopFont(.bodySmall, color: false)
            .foregroundStyle(color)
            .tint(NoopTheme.textPrimary)
            .focused($focused, equals: row.field)
            .fixedSize(horizontal: row.input != .text, vertical: false)
            .frame(minWidth: NoopTheme.Layout.xl, minHeight: NoopTheme.Layout.minTouchTarget, alignment: .trailing)
            // An empty field that may stay empty reads "Not set", with no unit after it.
            if let suffix = row.suffix, !(typed[row.field] ?? row.text).isEmpty {
                Text(verbatim: suffix)
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(row.isInvalid ? NoopTheme.recoveryLow : NoopTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    // One line beside the label, which wraps instead; stacked rows let it wrap.
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = row.field }
    }

    private func text(for row: ScorecardPhaseRow) -> Binding<String> {
        Binding(
            get: { typed[row.field] ?? row.text },
            set: { value in
                guard value != (typed[row.field] ?? row.text) else { return }
                typed[row.field] = value
                draft = CutScorecardPresenter.phaseDraft(draft, setting: row.field, to: value,
                                                         unitSystem: context.unitSystem(), locale: context.locale())
            })
    }

    // MARK: Start date

    private var startDate: Binding<Date> {
        Binding(
            get: { CutScorecardPresenter.phaseStartDate(draft, timeZone: context.timeZone()) ?? context.now() },
            set: { draft = CutScorecardPresenter.phaseDraft(draft, startingOn: $0, timeZone: context.timeZone()) })
    }

    /// Monday first, as the weekly series is counted.
    private var pickerCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone()
        calendar.locale = context.locale()
        calendar.firstWeekday = 2
        return calendar
    }
}
