import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 1 (weigh-in and scorecard), specification §10.3, frames C1 to C10 of
// `design/round6-scorecard/`. Step 1 weight, step 2 waist, one date for both. The decimal pad is up
// when the sheet opens, the last value is offered in the field and the next key replaces it, and the
// waist can be skipped, so a weigh-in is a few seconds.
//
// The sheet draws `WeighInSheetModel` and decides nothing: validity, hints, the week note and the
// button titles are the model's, and the fixed words are the presenter's.

/// The weigh-in sheet, as Settings and the scorecard screens present it. `editing` opens it with a
/// stored reading's values and instant.
struct WeighInSheet: View {
    var editing: WeighInHistoryRow?

    var body: some View {
        ScorecardContextReader { WeighInSheetScreen(context: $0, editing: editing) }
    }
}

struct WeighInSheetScreen: View {
    private let context: ScorecardContext
    @StateObject private var model: WeighInSheetModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var fieldFocused: Bool
    @State private var showsCalendar = false
    /// The prefilled value of each step while it is still untouched: drawn selected, and replaced
    /// by the next key.
    @State private var offeredWeight: String?
    @State private var offeredWaist: String?

    /// `model` and `showsCalendar` are for the debug demo, which opens the sheet in a given state.
    init(context: ScorecardContext, editing: WeighInHistoryRow? = nil, model: WeighInSheetModel? = nil,
         showsCalendar: Bool = false) {
        self.context = context
        _model = StateObject(wrappedValue: model ?? context.sheetModel(editing: editing))
        _showsCalendar = State(initialValue: showsCalendar)
    }

    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isSaving: Bool { model.phase == .saving }
    private var onWeight: Bool { model.step == .weight }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                dateControl
                if let note = model.dateNote {
                    Text(verbatim: note)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopTheme.Layout.s)
                }
                if !onWeight, !model.weightText.isEmpty { weightDoneRow }
                entry
                if let failure = model.failureMessage { failureNote(failure) }
                if stacks { actions }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.top, NoopTheme.Layout.l)
            .padding(.bottom, NoopTheme.Layout.l)
        }
        .scorecardDemoScroll()
        .scrollDismissesKeyboard(.never)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !stacks {
                actions
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .padding(.bottom, NoopTheme.Layout.s)
                    .background(NoopTheme.sheet)
            }
        }
        .background(NoopTheme.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .task {
            fieldFocused = !showsCalendar
            let weightWasEmpty = model.weightText.isEmpty
            let waistWasEmpty = model.waistText.isEmpty
            await model.prepare()
            // What `prepare` put in an empty field is an offer: the last reading.
            if weightWasEmpty, !model.weightText.isEmpty { offeredWeight = model.weightText }
            if waistWasEmpty, !model.waistText.isEmpty { offeredWaist = model.waistText }
            fieldFocused = !showsCalendar
        }
        .onChangeCompat(of: model.phase) { phase in
            if phase == .saved { dismiss() }
        }
        .onChangeCompat(of: model.step) { _ in
            showsCalendar = false
            fieldFocused = true
        }
    }

    // MARK: Header

    private var header: some View {
        let cancel = Button { dismiss() } label: {
            Text(verbatim: CutScorecardPresenter.cancelTitle)
                .noopFont(.body, color: false)
                .foregroundStyle(NoopTheme.textPrimary)
                .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.noopPress)
        .disabled(isSaving)
        .opacity(isSaving ? ScorecardLayout.busyOpacity : 1)
        let title = Text(verbatim: CutScorecardPresenter.weighInTitle)
            .noopFont(.navTitle)
            .accessibilityAddTraits(.isHeader)
        let step = Text(verbatim: CutScorecardPresenter.weighInStepText(model.step))
            .noopFont(.footnote)
        return Group {
            if stacks {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        cancel
                        Spacer(minLength: NoopTheme.Layout.s)
                        step.fixedSize(horizontal: false, vertical: true)
                    }
                    title.fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ZStack {
                    title
                    HStack {
                        cancel
                        Spacer(minLength: NoopTheme.Layout.s)
                        step
                    }
                }
            }
        }
    }

    // MARK: Date

    private var dateControl: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
            Button {
                showsCalendar.toggle()
                fieldFocused = !showsCalendar
            } label: {
                HStack(spacing: NoopTheme.Layout.s) {
                    Image(systemName: "calendar")
                        .noopFont(.chip, color: false)
                        .foregroundStyle(NoopTheme.textSecondary)
                        .accessibilityHidden(true)
                    Text(verbatim: CutScorecardPresenter.weighInDateText(
                        takenAt: model.takenAt, now: context.now(), timeZone: context.timeZone(),
                        locale: context.locale()))
                        .noopFont(.chip)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    FormKitChevron()
                }
                .padding(.horizontal, NoopTheme.Layout.m)
                .padding(.vertical, NoopTheme.Layout.s)
                .frame(minHeight: NoopTheme.Layout.pillHeight)
                .background {
                    RoundedRectangle(cornerRadius: stacks ? NoopTheme.Layout.tileRadius : NoopTheme.Layout.pillHeight,
                                     style: .continuous)
                        .fill(NoopTheme.control)
                }
                .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.noopPress)
            .disabled(isSaving)

            if showsCalendar {
                DatePicker(selection: $model.takenAt, in: ...context.now(),
                           displayedComponents: [.date, .hourAndMinute]) { EmptyView() }
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(NoopTheme.textSecondary)
                    .environment(\.calendar, pickerCalendar)
                    .environment(\.timeZone, context.timeZone())
                    .padding(NoopTheme.Layout.m)
                    .background {
                        RoundedRectangle(cornerRadius: NoopTheme.Layout.l, style: .continuous)
                            .fill(NoopTheme.control)
                    }
            }
        }
        .padding(.top, NoopTheme.Layout.s)
    }

    /// Monday first, as the weekly series is counted.
    private var pickerCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone()
        calendar.locale = context.locale()
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: Step 1, carried into step 2

    private var weightDoneRow: some View {
        HStack(spacing: NoopTheme.Layout.s) {
            ScorecardSignalGlyph(state: .met)
            Text(verbatim: CutScorecardPresenter.weightTitle)
                .noopFont(.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: CutScorecardPresenter.weighInValueText(model.weightText, unit: model.weightUnit))
                .noopFont(.rowTitle)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.back() } label: {
                Text(verbatim: CutScorecardPresenter.editTitle)
                    .noopFont(.pill, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.noopPress)
            .disabled(isSaving)
        }
        .padding(.horizontal, FormKitLayout.fieldHorizontal)
        .background {
            RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous)
                .fill(NoopTheme.control)
        }
        .padding(.top, NoopTheme.Layout.m)
    }

    // MARK: Entry

    private var entry: some View {
        let isError = onWeight ? model.weightHintIsError : model.waistHintIsError
        let hint = showsCalendar && !isError ? model.dateHint : (onWeight ? model.weightHint : model.waistHint)
        let label = onWeight ? CutScorecardPresenter.weightTitle : CutScorecardPresenter.waistTitle
        let unit = onWeight ? model.weightUnit : model.waistUnit
        let offered = (onWeight ? offeredWeight : offeredWaist) == fieldText.wrappedValue
            && !fieldText.wrappedValue.isEmpty
        let numberLayout = stacks
            ? AnyLayout(VStackLayout(spacing: NoopTheme.Layout.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s))
        return VStack(spacing: NoopTheme.Layout.s) {
            Text(verbatim: label).noopFont(.footnote)
            numberLayout {
                TextField(text: fieldText) { EmptyView() }
                    .keyboardType(.decimalPad)
                    .focused($fieldFocused)
                    .noopFont(.bigNumber, color: false)
                    .foregroundStyle(isError ? NoopTheme.recoveryLow : NoopTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .tint(NoopTheme.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, NoopTheme.Layout.xs)
                    .background {
                        if offered {
                            RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous)
                                .fill(NoopTheme.textPrimary.opacity(ScorecardLayout.selectionTint))
                        }
                    }
                    .disabled(isSaving || (!onWeight && !model.canEditWaist))
                    .accessibilityLabel(Text(verbatim: "\(label), \(unit)"))
                Text(verbatim: unit)
                    .noopFont(.rowNumber, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
            }
            Text(verbatim: hint)
                .noopFont(.footnote, color: false)
                .foregroundStyle(isError ? NoopTheme.recoveryLow : NoopTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NoopTheme.Layout.xl)
        .contentShape(Rectangle())
        .onTapGesture {
            showsCalendar = false
            fieldFocused = true
        }
    }

    /// The field of the current step. While the offered value is untouched the first key replaces
    /// it, as typing over a selection does; a delete clears it.
    private var fieldText: Binding<String> {
        Binding(
            get: { onWeight ? model.weightText : model.waistText },
            set: { typed in
                let current = onWeight ? model.weightText : model.waistText
                guard typed != current else { return }
                var next = typed
                if let offer = onWeight ? offeredWeight : offeredWaist {
                    if current == offer { next = Self.replacing(offer, with: typed) }
                    if onWeight { offeredWeight = nil } else { offeredWaist = nil }
                }
                if onWeight { model.weightText = next } else { model.waistText = next }
            })
    }

    /// What typing over the whole of `selected` leaves: the characters `typed` added to it, or
    /// nothing after a delete.
    private static func replacing(_ selected: String, with typed: String) -> String {
        guard typed.count > selected.count else { return "" }
        var added = Array(typed)
        var rest = Array(selected)
        while let a = added.first, let b = rest.first, a == b {
            added.removeFirst()
            rest.removeFirst()
        }
        while let a = added.last, let b = rest.last, a == b {
            added.removeLast()
            rest.removeLast()
        }
        return String(added)
    }

    private func failureNote(_ text: String) -> some View {
        Text(verbatim: text)
            .noopFont(.footnote, color: false)
            .foregroundStyle(NoopTheme.recoveryLow)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FormKitLayout.fieldHorizontal)
            .padding(.vertical, FormKitLayout.fieldVertical)
            .background {
                RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous)
                    .fill(NoopTheme.recoveryLow.opacity(ScorecardLayout.dangerTint))
            }
            .padding(.bottom, NoopTheme.Layout.m)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: NoopTheme.Layout.xs) {
            Button {
                if onWeight {
                    model.advance()
                } else {
                    Task { await model.save() }
                }
            } label: {
                Text(verbatim: model.primaryTitle)
            }
            .buttonStyle(NoopPrimaryButton())
            .disabled(onWeight ? !model.canAdvance : !model.canSave)

            if !onWeight, !model.weightText.isEmpty {
                Button { Task { await model.skipWaist() } } label: {
                    Text(verbatim: CutScorecardPresenter.skipTitle)
                        .noopFont(.rowTitle)
                        .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.noopPress)
                .disabled(isSaving)
                .opacity(isSaving ? ScorecardLayout.busyOpacity : 1)
                if model.failureMessage == nil {
                    Text(verbatim: model.skipNote)
                        .noopFont(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, NoopTheme.Layout.s)
    }
}
